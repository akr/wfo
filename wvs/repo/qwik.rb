require 'htree'

class WVS::Qwik < WVS::Repo
  def self.checkout_if_possible(page)
    if %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ page
      try_checkout(page)
    else
      nil
    end
  end

  def self.try_checkout(page)
    edit_url = URI(page.base_uri.to_s.sub(/\.html/, '.edit'))
    self.checkout(edit_url)
  end

  def self.checkout(edit_url)
    update_page_str = WVS::WebClient.read(edit_url)
    update_page_tree = HTree(update_page_str)
    if update_page_str.base_uri != edit_url
      raise "qwikWeb edit page redirected"
    end
    form = find_textarea_form(update_page_tree, edit_url)
    self.new(form, edit_url)
  end

  def self.find_textarea_form(page, uri)
    page.traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form.traverse_element('{http://www.w3.org/1999/xhtml}textarea') {
        return WVS::Form.make(uri, form)
      }
    }
    raise "textarea not found in #{uri}"
  end

  def initialize(form, uri)
    @form = form
    @uri = uri
  end

  def current_text
    @form.fetch('contents').dup
  end

  def replace_text(text)
    @form.set('contents', text)
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
    self.class.checkout(@uri)
  end

  def self.qwik_auth_handler(webclient, uri, req, resp)
    qwik_typekey_auth_handler(webclient, uri, req, resp)
  end

  def self.qwik_reqauth_checker(webclient, uri, req, resp)
    %r{<a href=".login"\n>Login</a\n>} =~ resp.body
  end

  def self.qwik_typekey_auth_handler(webclient, uri, req, resp)
    unless %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ resp.body
      return nil
    end
    unless %r{<a href="\.login"\n>Login</a\n>} =~ resp.body
      return nil
    end
    qwik_login_uri = uri + ".login"
    req = Net::HTTP::Get.new(qwik_login_uri.request_uri)
    resp = webclient.do_request(qwik_login_uri, req)
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
    resp = webclient.do_request(qwik_typekey_uri, req)
    return nil if resp.code != '302'
    typekey_uri = URI(resp['Location'])

    resp = WVS::Auth.typekey_login(webclient, typekey_uri)

    if resp.code == '302' # codeblog
      codeblog_uri = URI(resp['Location'])
      req = Net::HTTP::Get.new(codeblog_uri.request_uri)
      resp = webclient.do_request(codeblog_uri, req)
    end

    return nil if resp.code != '200'

    req = Net::HTTP::Get.new(uri.request_uri)

    return uri, req
  end

end
