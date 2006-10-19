require 'htree'

class WVS::Qwik < WVS::Repo
  def self.applicable?(page)
    %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ page
  end

  def self.find_stable_uri(page)
    last_request_uri = page.last_request_uri.to_s
    if /\.html\z/ =~ last_request_uri
      return URI(last_request_uri.sub(/\.html\z/, '.edit'))
    else
      tree = HTree(page)
      tree.traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
        href = e.get_attr('href')
        if href && /\.edit\z/ =~ href
          return page.last_request_uri + href
        end
      }
    end
    raise "edit page could not find : #{last_request_uri}"
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WVS::WebClient.read_decode(uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != uri
      raise "qwikWeb edit page redirected"
    end
    form, textarea_name = find_textarea_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name)
  end

  def self.find_textarea_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      form.each_textarea {|name, value| return form, name }
    }
    raise "textarea not found in #{page.request_uri}"
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
    resp = WVS::WebClient.do_request(req)
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

def (WVS::Auth).qwik_reqauth_checker(webclient, resp)
  %r{<a href=".login"\n>Login</a\n>} =~ resp.body
end

def (WVS::Auth).qwik_auth_handler(webclient, resp)
  qwik_auth_handler_typekey(webclient, resp)
end

def (WVS::Auth).qwik_auth_handler_typekey(webclient, resp)
  uri = resp.uri
  unless %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ resp.body
    return nil
  end
  unless %r{<a href="\.login"\n>Login</a\n>} =~ resp.body
    return nil
  end
  qwik_login_uri = uri + ".login"
  resp = webclient.do_request_state(WVS::ReqHTTP.get(qwik_login_uri))
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

  resp = webclient.do_request_state(WVS::ReqHTTP.get(qwik_typekey_uri))
  return nil if resp.code != '302'
  typekey_uri = URI(resp['Location'])

  resp = WVS::Auth.typekey_login(webclient, typekey_uri)

  if resp.code == '302' # codeblog
    codeblog_uri = URI(resp['Location'])
    resp = webclient.do_request_state(WVS::ReqHTTP.get(codeblog_uri))
  end

  return nil if resp.code != '200'

  return WVS::ReqHTTP.get(uri)
end

