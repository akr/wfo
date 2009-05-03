# wfo/webclient.rb - stateful web client library
#
# Copyright (C) 2006,2007 Tanaka Akira  <akr@fsij.org>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 'net/https'
require 'wfo/form'
require 'wfo/cookie'
require 'wfo/auth'
require 'keyring'

class WFO::WebClient
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

  def self.read(uri, verify, opts={})
    Thread.current[:webclient].read(uri, verify, opts)
  end

  def self.read_decode(uri, opts={})
    Thread.current[:webclient].read_decode(uri, opts)
  end

  def self.read_decode_nocheck(uri, opts={})
    Thread.current[:webclient].read_decode_nocheck(uri, opts)
  end

  def self.do_request(request, verify)
    Thread.current[:webclient].do_request(request, verify)
  end

  def initialize
    @auth_agents = {}
    @cookies = {}
  end

  def register_http_auth_agent(agent)
    agent.each_protection_domain_uri {|uri|
      canonical_root_uri = uri.dup
      canonical_root_uri.path = ""
      canonical_root_uri.query = nil
      canonical_root_uri.fragment = nil
      canonical_root_uri = canonical_root_uri.to_s
      path_pat = /\A#{Regexp.quote uri.path}/
      @auth_agents[canonical_root_uri] ||= []
      @auth_agents[canonical_root_uri] << [path_pat, agent]
    }
  end

  def make_request_http_authenticated(request)
    canonical_root_url = request.uri.dup
    canonical_root_url.path = ""
    canonical_root_url.query = nil
    canonical_root_url.fragment = nil
    canonical_root_url = canonical_root_url.to_s
    agents = @auth_agents[canonical_root_url]
    return if !agents
    path = request.uri.path
    agent = nil
    matchlen = -1
    agents.each {|path_pat, a|
      if path_pat =~ path
        if matchlen < $&.length
          agent = a
          matchlen = $&.length
        end
      end
    }
    if agent
      request['Authorization'] = agent.generate_authorization(request)
    end
  end

  def update_cookies(uri, set_cookie_field)
    cs = WFO::Cookie.parse(uri, set_cookie_field)
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

  def do_request(request, verify)
    results = do_redirect_requests(request, verify)
    results.last.last
  end

  def do_redirect_requests(request, verify)
    results = []
    while true
      response = do_request_state(request, verify)
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
        request = WFO::ReqHTTP.get(redirect)
      else
        break
      end
    end
    results
  end

  def do_request_state(request, verify)
    while true
      make_request_http_authenticated(request)
      resp = do_request_cookie(request, verify)
      checker_results = WFO::Auth.reqauth_checker.map {|checker|
        checker.call(self, resp, verify)
      }
      checker_results.compact!
      return resp if checker_results.empty?
      if 1 < checker_results.length
        warn "more than one authhandler"
      end
      if !checker_results.first.call
        raise "authhandler failed: #{resp.code} #{resp.message} in #{resp.uri}"
      end
    end
  end

  def do_request_cookie(request, verify)
    insert_cookie_header(request)
    resp = do_request_simple(request, verify)
    update_cookies(request.uri, resp['Set-Cookie']) if resp['Set-Cookie']
    resp
  end

  def do_request_simple(req, verify)
    if proxy_uri = req.uri.find_proxy
      # xxx: proxy authentication
      klass = Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port)
    else
      klass = Net::HTTP
    end
    h = klass.new(req.uri.host, req.uri.port)
    if req.uri.scheme == 'https'
      h.use_ssl = true
      # TODO: This must be generic.
      if verify
        h.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end
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
      req.do_http(h)
    }
  end

  def read(uri, verify, header={})
    request = WFO::ReqHTTP.get(uri)
    header.each {|k, v| request[k] = v }

    response = do_request(request, verify)
    if response.code != '200'
      raise "request failed: #{response.code} #{response.message} in #{response.uri}"
    end

    result = response.body
    OpenURI::Meta.init result
    result.status = [response.code, response.message]
    result.base_uri = response.uri # xxx: Content-Location
    response.each {|name,value| result.meta_add_field name, value }
    result
  end

  def read_decode(uri, verify, header={})
    page_str = self.read(uri, verify, header)
    unless charset = page_str.charset
      charset = page_str.guess_charset
    end
    result = page_str.decode_charset(charset)
    round_trip = result.encode_charset(charset)
    if page_str != round_trip
      raise "The locale character encoding, #{Mconv.internal_mime_charset}, cannot represent the page: #{uri}"
    end
    OpenURI::Meta.init result, page_str
    return result, charset
  end

  def read_decode_nocheck(uri, verify, header={})
    page_str = self.read(uri, verify, header)
    unless charset = page_str.charset
      charset = page_str.guess_charset
    end
    result = page_str.decode_charset(charset)
    OpenURI::Meta.init result, page_str
    return result, charset
  end
end

module WFO
  class ReqHTTP
    def self.get(uri)
      self.new('GET', uri)
    end

    def self.post(uri, content_type, query)
      self.new('POST', uri, {'Content-Type'=>content_type}, query)
    end

    def initialize(method, uri, header={}, body=nil)
      @method = method.upcase
      @uri = uri
      @header = header
      @body = body
    end
    attr_reader :uri, :body

    def pretty_print(q)
      q.object_group(self) {
        q.breakable
        q.text @method
        q.breakable
        q.text @uri.to_s
        @header.each {|n,v|
          q.breakable
          q.text n
          q.text ": "
          q.text v
        }
        if @body
          @body.each_line {|line|
            q.breakable
            q.text line
          }
        end
      }
    end

    alias inspect pretty_print_inspect

    def http_method
      @method
    end

    def []=(field_name, field_value)
      @header[field_name] = field_value
    end

    def each_header
      @header.each {|k,v| yield k, v }
    end

    def do_http(http)
      case @method
      when "GET"
        req = Net::HTTP::Get.new(@uri.request_uri)
        @header.each {|field_name, field_value| req[field_name] = field_value }
        #pp self
        resp = http.request(req)
        result = WFO::RespHTTP.new(self, resp)
        #pp result
      when "POST"
        req = Net::HTTP::Post.new(@uri.request_uri)
        @header.each {|field_name, field_value| req[field_name] = field_value }
        resp = http.request(req, @body)
        result = WFO::RespHTTP.new(self, resp)
      else
        raise ArgumentError, "unexpected method: #{@method}"
      end
      result
    end
  end

  class RespHTTP
    def initialize(request, resp)
      @request = request
      @resp = resp
    end
    attr_reader :request

    def pretty_print(q)
      q.object_group(self) {
        q.breakable
        q.group {
          q.text @request.http_method
          q.breakable
          q.text @request.uri.to_s
        }
        @request.each_header {|n,v|
          q.breakable
          q.text n
          q.text ": "
          q.text v.inspect
        }
        if @request.body
          @request.body.each_line {|line|
            q.breakable
            q.text line
          }
        end
        q.breakable
        q.group {
          q.text @resp.code
          q.breakable
          q.text @resp.message
        }
        @resp.canonical_each {|k, v|
          q.breakable
          q.text k
          q.text ': '
          q.text v.inspect
        }
        if @resp.body
          @resp.body.each_line {|line|
            q.breakable
            q.text line.inspect
          }
        end
      }
    end

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
