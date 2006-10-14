require 'net/https'
require 'wvs/form'
require 'wvs/cookie'
require 'wvs/auth'
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
    @auth_handler = []
    @reqauth_checker = []
    @auth_handler << WVS::Auth.method(:codeblog_handler)
    @auth_handler << WVS::Qwik.method(:qwik_auth_handler)
    @reqauth_checker << WVS::Qwik.method(:qwik_reqauth_checker)

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

  def do_request(uri, req)
    do_request_redirect(uri, req)
  end

  def do_request_redirect(uri, req)
    while true
      resp = do_request_cookie(uri, req)
      if /\A(?:301|302|303|307)\z/ =~ resp.code && resp['location']
        p resp
        p resp.body
        # RFC 1945 - Hypertext Transfer Protocol -- HTTP/1.0
        #  301 Moved Permanently
        #  302 Moved Temporarily
        # RFC 2068 - Hypertext Transfer Protocol -- HTTP/1.1
        #  301 Moved Permanently
        #  302 Moved Temporarily
        #  303 See Other
        # RFC 2616 - Hypertext Transfer Protocol -- HTTP/1.1
        #  301 Moved Permanently
        #  302 Found
        #  303 See Other
        #  307 Temporary Redirect
        redirect = URI(resp['location'])
        # Although it violates RFC2616, Location: field may have relative
        # URI.  It is converted to absolute URI using uri as a base URI.
        redirect = uri + redirect if redirect.relative?
        req = Net::HTTP::Get.new(redirect.request_uri)
        uri = redirect
        p req
        p uri
      else
        break
      end
    end
    resp
  end

  def do_request_cookie(uri, req)
    insert_cookie_header(uri, req)
    resp = do_request_simple(uri, req)
    update_cookies(uri, resp['Set-Cookie']) if resp['Set-Cookie']
    resp
  end

  def do_request_simple(uri, req)
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
      h.request req
    }
  end

  def read(uri, header={})
    req = Net::HTTP::Get.new(uri.request_uri)
    header.each {|k, v| req[k] = v }

    while true
      resp = do_request(uri, req)
      break if resp.code == '200' && @reqauth_checker.all? {|checker| !checker.call(self, uri, req, resp) }
      r = nil
      @auth_handler.each {|h|
        if r = h.call(self, uri, req, resp)
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
