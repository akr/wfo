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

  def self.read_decode(uri, opts={})
    Thread.current[:webclient].read_decode(uri, opts)
  end

  def self.read_decode_nocheck(uri, opts={})
    Thread.current[:webclient].read_decode_nocheck(uri, opts)
  end

  def self.do_request(request)
    Thread.current[:webclient].do_request(request)
  end

  def initialize
    @basic_credentials = {}
    @cookies = {}
  end

  def add_basic_credential(canonical_root_url, realm, path_pat, credential)
    @basic_credentials[canonical_root_url] ||= []
    @basic_credentials[canonical_root_url] << [realm, path_pat, credential]
  end

  def make_request_basic_authenticated(request)
    canonical_root_url = request.uri.dup
    canonical_root_url.path = ""
    canonical_root_url.query = nil
    canonical_root_url.fragment = nil
    canonical_root_url = canonical_root_url.to_s
    return if !@basic_credentials[canonical_root_url]
    path = request.uri.path
    @basic_credentials[canonical_root_url].each {|realm, path_pat, credential|
      if path_pat =~ path
        request['Authorization'] = "Basic #{credential}"
        break
      end
    }
  end

  def update_cookies(uri, set_cookie_field)
    cs = WVS::Cookie.parse(uri, set_cookie_field)
    cs.each {|c|
      key = [c.domain, c.path, c.name].freeze
      @cookies[key] = c
    }
  end

  def insert_cookie_header(request)
    cs = @cookies.reject {|(domain, path, name), c| !c.match?(request.uri) }
    if !cs.empty?
      request['Cookie'] = cs.map {|(domain, path, name), c| c.encode_cookie_field }.join('; ')
    end
  end

  def do_request(request)
    results = do_redirect_requests(request)
    results.last.last
  end

  def do_redirect_requests(request)
    results = []
    while true
      response = do_request_state(request)
      results << [request, response]
      if /\A(?:301|302|303|307)\z/ =~ response.code && response['location']
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
        redirect = URI(response['location'])
        # Although it violates RFC2616, Location: field may have relative
        # URI.  It is converted to absolute URI using uri as a base URI.
        redirect = request.uri + redirect if redirect.relative?
        request = WVS::ReqHTTP.get(redirect)
      else
        break
      end
    end
    results
  end

  def do_request_state(request)
    make_request_basic_authenticated(request)
    insert_cookie_header(request)
    resp = do_request_simple(request)
    update_cookies(request.uri, resp['Set-Cookie']) if resp['Set-Cookie']
    resp
  end

  def do_request_simple(req)
    if proxy_uri = req.uri.find_proxy
      # xxx: proxy authentication
      klass = Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port)
    else
      klass = Net::HTTP
    end
    h = klass.new(req.uri.host, req.uri.port)
    if req.uri.scheme == 'https'
      h.use_ssl = true
      h.verify_mode = OpenSSL::SSL::VERIFY_PEER
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      h.cert_store = store
    end
    h.start {
      if req.uri.scheme == 'https'
        sock = h.instance_variable_get(:@socket)
        if sock.respond_to?(:io)
          sock = sock.io # 1.9
        else
          sock = sock.instance_variable_get(:@socket) # 1.8
        end
        sock.post_connection_check(req.uri.host)
      end
      WVS::RespHTTP.new(req, h.request(req.req))
    }
  end

  def read(uri, header={})
    request = WVS::ReqHTTP.get(uri)
    header.each {|k, v| request[k] = v }

    while true
      response = do_request(request)
      break if response.code == '200' &&
               WVS::Auth.reqauth_checker.all? {|checker|
                 !checker.call(self, response)
               }
      request = nil
      WVS::Auth.auth_handler.each {|h|
        if request = h.call(self, response)
          break
        end
      }
      if request == nil
        raise "no handler for #{response.code} #{response.message} in #{response.uri}"
      end
    end

    result = response.body
    OpenURI::Meta.init result
    result.status = [response.code, response.message]
    result.base_uri = response.uri # xxx: Content-Location
    response.each {|name,value| result.meta_add_field name, value }
    result
  end

  def read_decode(uri, header={})
    page_str = self.read(uri, header)
    unless charset = page_str.charset
      charset = page_str.guess_charset
    end
    result = page_str.decode_charset(charset)
    round_trip = result.encode_charset(charset)
    if page_str != round_trip
      raise "cannot decode in round trip manner: #{uri}"
    end
    OpenURI::Meta.init result, page_str
    return result, charset
  end

  def read_decode_nocheck(uri, header={})
    page_str = self.read(uri, header)
    unless charset = page_str.charset
      charset = page_str.guess_charset
    end
    result = page_str.decode_charset(charset)
    OpenURI::Meta.init result, page_str
    return result, charset
  end
end

module WVS
  class ReqHTTP
    def self.get(uri)
      req = Net::HTTP::Get.new(uri.request_uri)
      self.new(uri, req)
    end

    def self.post(uri, content_type, query)
      req = Net::HTTP::Post.new(uri.request_uri)
      req.body = query
      req['Content-Type'] = content_type
      self.new(uri, req)
    end

    def initialize(uri, req)
      @uri = uri
      @req = req
    end
    attr_reader :uri, :req

    def []=(field_name, field_value)
      @req[field_name] = field_value
    end
  end

  class RespHTTP
    def initialize(request, resp)
      @request = request
      @resp = resp
    end
    attr_reader :request, :resp

    def uri
      @request.uri
    end

    def code
      @resp.code
    end

    def message
      @resp.message
    end

    def [](field_name)
      @resp[field_name]
    end

    def each
      @resp.each {|field_name, field_value|
        yield field_name, field_value
      }
      nil
    end

    def body
      @resp.body
    end
  end
end
