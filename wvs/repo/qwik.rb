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

  def self.qwik_typekey_auth_handler(webclient, uri, req, resp)
    unless resp.code == '500' &&
           %r{<a href=".login"\n>Login</a\n>} =~ resp.body
      return nil
    end
    qwik_login_uri = uri + ".login"
    qwik_typekey_uri = nil
    HTree(qwik_login_uri).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      if e.extract_text.to_s == "Login by TypeKey"
        qwik_typekey_uri = qwik_login_uri + e.get_attr('href')
      end
    }
    return nil if !qwik_typekey_uri
    req = Net::HTTP::Get.new(qwik_typekey_uri.request_uri)
    resp = webclient.do_request(qwik_typekey_uri, req)
    return nil if resp.code != '302'
    typekey_uri = URI(resp['Location'])

    typekey_login_form = nil
    HTree(typekey_uri).traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form = WVS::Form.make(typekey_uri, form)
      if form.has?('username') && form.has?('password')
        typekey_login_form = form
        break
      end
    }
    return nil if !typekey_login_form
    KeyRing.with_authinfo(KeyRing.typekey_protection_domain) {|username, password|
      typekey_login_form.set('username', username)
      typekey_login_form.set('password', password)
      typekey_login_form.make_request {|req|
        resp = webclient.do_request(typekey_login_form.action_uri, req)
      }
    }
    # The password vanishing is not perfect, unfortunately.
    # arr = []; ObjectSpace.each_object(String) {|s| arr << s }; arr.each {|v| p v }
    webclient.update_cookies(typekey_login_form.action_uri, resp['Set-Cookie']) if resp['Set-Cookie']

    if resp.code == '200' # send email address or not?
      email_form = nil
      HTree(resp.body).traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
        email_form = WVS::Form.make(typekey_login_form.action_uri, form)
        break
      }
      req = email_form.make_request
      webclient.insert_cookie_header(email_form.action_uri, req)
      resp = webclient.do_request(email_form.action_uri, req)
    end

    return nil if resp.code != '302'
    return_uri = URI(resp['Location'])

    req = Net::HTTP::Get.new(return_uri.request_uri)
    webclient.insert_cookie_header(return_uri, req)
    resp = webclient.do_request(return_uri, req)
    webclient.update_cookies(return_uri, resp['Set-Cookie'])

    return nil if resp.code != '200'

    req = Net::HTTP::Get.new(uri.request_uri)
    webclient.insert_cookie_header(uri, req)

    return uri, req
  end

end
