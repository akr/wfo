require 'htree'

class WVS::Qwik < WVS::Repo
  def self.applicable?(page)
    %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ page
  end

  def self.find_stable_uri(page)
    URI(page.base_uri.to_s.sub(/\.html/, '.edit'))
  end

  def self.make_accessor(edit_uri)
    page_str = WVS::WebClient.read(edit_uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != edit_uri
      raise "qwikWeb edit page redirected"
    end
    form, textarea_name = find_textarea_form(page_tree, page_tree.base_uri, page_str.last_request_uri)
    self.new(form, edit_uri, textarea_name)
  end

  def self.find_textarea_form(page, base_uri, referer_uri)
    page.traverse_html_form {|form|
      form.each_textarea {|name, value| return form, name }
    }
    raise "textarea not found in #{uri}"
  end

  def initialize(form, uri, textarea_name)
    @form = form
    @uri = uri
    @textarea_name = textarea_name
  end
  attr_reader :form, :textarea_name

  def current_text
    @form.fetch(@textarea_name).dup
  end

  def replace_text(text)
    @form.set(@textarea_name, text)
  end

  def commit
    req = @form.make_request('save')
    req["Referer"] = @uri.to_s
    resp = WVS::WebClient.do_request(@form.action_uri, req)
    return if resp.code == '200'
    raise "HTTP POST error: #{resp.code} #{resp.message}"
  end

  def recommended_filename
    @form.action_uri.to_s.sub(%r{\A.*/}, '').sub(/\.save\z/, '')
  end

  def reload
    self.class.make_accessor(@uri)
  end
end

def (WVS::Auth).qwik_reqauth_checker(webclient, uri, req, resp)
  %r{<a href=".login"\n>Login</a\n>} =~ resp.body
end

def (WVS::Auth).qwik_auth_handler(webclient, uri, req, resp)
  qwik_auth_handler_typekey(webclient, uri, req, resp)
end

def (WVS::Auth).qwik_auth_handler_typekey(webclient, uri, req, resp)
  unless %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ resp.body
    return nil
  end
  unless %r{<a href="\.login"\n>Login</a\n>} =~ resp.body
    return nil
  end
  qwik_login_uri = uri + ".login"
  req = Net::HTTP::Get.new(qwik_login_uri.request_uri)
  resp = webclient.do_request_state(qwik_login_uri, req)
  if resp.code == '200'
    qwik_typekey_uri = nil
    HTree(resp.body).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      if e.extract_text.to_s == "Login by TypeKey"
        qwik_typekey_uri = qwik_login_uri + e.get_attr('href')
      end
    }
    return nil if !qwik_typekey_uri
  elsif resp.code == '302' && %r{/\.typekey\z} =~ resp['Location']
    # "https://www.codeblog.org/.typekey"
    # "https://www.codeblog.org/wg-chairs/.typekey"
    qwik_typekey_uri = URI(resp['Location'])
  else
    return nil
  end

  req = Net::HTTP::Get.new(qwik_typekey_uri.request_uri)
  resp = webclient.do_request_state(qwik_typekey_uri, req)
  return nil if resp.code != '302'
  typekey_uri = URI(resp['Location'])

  resp = WVS::Auth.typekey_login(webclient, typekey_uri)

  if resp.code == '302' # codeblog
    codeblog_uri = URI(resp['Location'])
    req = Net::HTTP::Get.new(codeblog_uri.request_uri)
    resp = webclient.do_request_state(codeblog_uri, req)
  end

  return nil if resp.code != '200'

  req = Net::HTTP::Get.new(uri.request_uri)

  return uri, req
end

