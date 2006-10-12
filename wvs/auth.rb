module WVS::Auth
  module_function

  def codeblog_handler(webclient, uri, req, resp)
    unless resp.code == '403' &&
           uri.scheme == 'https' &&
           uri.host == 'www.codeblog.org' &&
           uri.port == 443
      return nil
    end
    errpage = resp.body
    return nil if /Log in via TypeKey/ !~ errpage
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
    sign_in_form = nil
    HTree(typekey_uri).traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form = WVS::Form.make(typekey_uri, form)
      if form.has?('username') && form.has?('password')
        sign_in_form = form
        break
      end
    }
    return nil if !sign_in_form
    KeyRing.with_authinfo(KeyRing.typekey_protection_domain) {|username, password|
      sign_in_form.set('username', username)
      sign_in_form.set('password', password)
      referer = typekey_uri
      sign_in_form.make_request(nil) {|req|
        req["Referer"] = referer.to_s
        resp = webclient.do_request(sign_in_form.action_uri, req)
      }
    }
    # The password vanishing is not perfect, unfortunately.
    # arr = []; ObjectSpace.each_object(String) {|s| arr << s }; arr.each {|v| p v }
    return nil if resp.code != '302'
    codeblog_uri = nil
    cookies = []
    resp.canonical_each {|k, v|
      case k
      when /\ALocation\z/i
        codeblog_uri = URI(v)
      when /\ASet-Cookie\z/i
        webclient.update_cookies(sign_in_form.action_uri, v)
      end
    }

    req = Net::HTTP::Get.new(codeblog_uri.request_uri)
    webclient.insert_cookie_header(codeblog_uri, req)
    resp = webclient.do_request(codeblog_uri, req)
    codeblog_uri2 = nil
    resp.canonical_each {|k, v|
      case k
      when /\ALocation\z/i
        codeblog_uri2 = URI(v)
      when /\ASet-Cookie\z/i
        webclient.update_cookies(codeblog_uri, v)
      end
    }

    req = Net::HTTP::Get.new(codeblog_uri2.request_uri)
    webclient.insert_cookie_header(codeblog_uri2, req)

    return codeblog_uri2, req
  end
end
