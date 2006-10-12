require 'net/https'
require 'wvs/form'
require 'wvs/cookie'
require 'keyring'

class WVS::WebClient
  def self.do
    webclient = self.new
    old = Thread.current[:webclient]
    begin
      Thread.current[:webclient] = webclient
      yield
    ensure
      Thread.current[:webclient] = old
    end
  end

  def self.read(uri, opts={})
    Thread.current[:webclient].read(uri, opts)
  end

  def self.do_request(uri, req)
    Thread.current[:webclient].do_request(uri, req)
  end

  def initialize
    @handler = []
    @handler << method(:codeblog_handler)

    @cookies = {}
  end

  def update_cookies(uri, set_cookie_field)
    cs = WVS::Cookie.parse(uri, set_cookie_field)
    cs.each {|c|
      key = [c.domain, c.path, c.name].freeze
      @cookies[key] = c
    }
  end

  def insert_cookie_header(uri, req)
    cs = @cookies.reject {|(domain, path, name), c| !c.match?(uri) }
    if !cs.empty?
      req['Cookie'] = cs.map {|(domain, path, name), c| c.encode_cookie_field }.join('; ')
    end
  end

  def codeblog_handler(uri, req, resp)
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
        resp = do_request(sign_in_form.action_uri, req)
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
        update_cookies(sign_in_form.action_uri, v)
      end
    }

    req = Net::HTTP::Get.new(codeblog_uri.request_uri)
    insert_cookie_header(codeblog_uri, req)
    resp = do_request(codeblog_uri, req)
    codeblog_uri2 = nil
    resp.canonical_each {|k, v|
      case k
      when /\ALocation\z/i
        codeblog_uri2 = URI(v)
      when /\ASet-Cookie\z/i
        update_cookies(codeblog_uri, v)
      end
    }

    req = Net::HTTP::Get.new(codeblog_uri2.request_uri)
    insert_cookie_header(codeblog_uri2, req)

    return codeblog_uri2, req
  end

  def do_request(uri, req)
    insert_cookie_header(uri, req)
    h = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      h.use_ssl = true
      h.verify_mode = OpenSSL::SSL::VERIFY_PEER
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      h.cert_store = store
    end
    h.start {
      if uri.scheme == 'https'
        sock = h.instance_variable_get(:@socket)
        if sock.respond_to?(:io)
          sock = sock.io # 1.9
        else
          sock = sock.instance_variable_get(:@socket) # 1.8
        end
        sock.post_connection_check(uri.host)
      end
      resp = h.request req
      resp
    }
  end

  def read(uri, header={})
    req = Net::HTTP::Get.new(uri.request_uri)
    header.each {|k, v| req[k] = v }

    while true
      resp = do_request(uri, req)
      break if resp.code == '200'
      r = nil
      @handler.each {|h|
        if r = h.call(uri, req, resp)
          uri, req = r
          break
        end
      }
      if r == nil
        raise "no handler for #{resp.code} #{resp.message} in #{uri}"
      end
    end

    result = resp.body
    OpenURI::Meta.init result
    result.status = [resp.code, resp.message]
    result.base_uri = uri
    resp.each {|name,value| result.meta_add_field name, value }
    result
  end

  def self.successful_controls(form, submit_name=nil)
    controls = WVS::WebClient.extract_controls(form)
    successful = []
    has_submit = false
    controls.each {|type, name, value, *rest|
      case type
      when :submit_button
        if !has_submit && name == submit_name
          successful << [name, value]
          has_submit = true
        end
      when :checkbox
        checked = rest[0]
        successful << [name, value] if checked
      when :hidden, :text
        successful << [name, value]
      else
        raise "unexpected control type: #{type}"
      end
    }
    successful
  end

  def self.extract_controls(form)
    result = []
    form.traverse_element(
      '{http://www.w3.org/1999/xhtml}input',
      '{http://www.w3.org/1999/xhtml}button',
      '{http://www.w3.org/1999/xhtml}select',
      '{http://www.w3.org/1999/xhtml}textarea') {|control|
      name = control.get_attr('name')
      next if !name
      case control.name
      when '{http://www.w3.org/1999/xhtml}input'
        next if control.get_attr('disabled')
        type = control.get_attr('type')
        type = type ? type.downcase : 'text'
        case type
        when 'text'
          result << [:text, name, control.get_attr('value').to_s]
        when 'hidden'
          result << [:hidden, name, control.get_attr('value').to_s]
        when 'password'
          result << [:hidden, name, control.get_attr('value').to_s]
        when 'submit'
          result << [:submit_button, name, control.get_attr('value').to_s]
        when 'checkbox'
          checked = control.get_attr('checked') ? :checked : nil
          result << [:checkbox, name, control.get_attr('value').to_s, checked]
        else
          raise "unexpected input type : #{type}"
        end
      when '{http://www.w3.org/1999/xhtml}button'
        next if control.get_attr('disabled')
      when '{http://www.w3.org/1999/xhtml}select'
        next if control.get_attr('disabled')
      when '{http://www.w3.org/1999/xhtml}textarea'
        next if control.get_attr('disabled')
        result << [:text, name, control.extract_text.to_s]
      else
        raise "unexpected control : #{control.name}"
      end
    }
    result
  end
end
