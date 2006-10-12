module WVS::Auth
  module_function

  def codeblog_handler(webclient, uri, req, resp)
    unless resp.code == '403' &&
           uri.scheme == 'https' &&
           uri.host == 'www.codeblog.org' &&
           uri.port == 443
      return nil
    end
    apache_authtypekey_handler(webclient, uri, req, resp)
  end

  def apache_authtypekey_handler(webclient, uri, req, resp)
    errpage = resp.body
    return nil if />Log in via TypeKey</ !~ errpage
    # It seems a login page generated by login.pl in Apache-AuthTypeKey.
    typekey_uri = nil
    HTree(errpage).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      if href = e.get_attr('href')
        href = URI(href)
        if href.host == 'www.typekey.com'
          typekey_uri = href
          break
        end
      end
    }
    return nil if !typekey_uri
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
    return nil if resp.code != '302'
    return_uri = URI(resp['Location'])
    webclient.update_cookies(typekey_login_form.action_uri, resp['Set-Cookie'])

    req = Net::HTTP::Get.new(return_uri.request_uri)
    webclient.insert_cookie_header(return_uri, req)
    resp = webclient.do_request(return_uri, req)
    return nil if resp.code != '302'
    destination_uri = URI(resp['Location'])
    webclient.update_cookies(return_uri, resp['Set-Cookie'])

    req = Net::HTTP::Get.new(destination_uri.request_uri)
    webclient.insert_cookie_header(destination_uri, req)

    return destination_uri, req
  end
end
