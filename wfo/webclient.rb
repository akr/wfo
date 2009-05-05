# wfo/webclient.rb - stateful web client library
#
# Copyright (C) 2006,2007,2009 Tanaka Akira  <akr@fsij.org>
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

  def self.ssl_verify_default
    Thread.current[:webclient].ssl_verify_default
  end

  def self.ssl_verify_default=(bool)
    Thread.current[:webclient].ssl_verify_default = bool
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
    @auth_agents = {}
    @cookies = {}
    @ssl_verify_default = true
  end
  attr_accessor :ssl_verify_default

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
        request = WFO::ReqHTTP.get(redirect)
      else
        break
      end
    end
    results
  end

  def do_request_state(request)
    while true
      make_request_http_authenticated(request)
      #pp request
      resp = do_request_cookie(request)
      #pp resp
      #puts

      checker_results = WFO::Auth.reqauth_checker.map {|checker|
        checker.call(self, resp)
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

  def do_request_cookie(request)
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
      if @ssl_verify_default
        h.verify_mode = OpenSSL::SSL::VERIFY_PEER
      else
        h.verify_mode = OpenSSL::SSL::VERIFY_NONE
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

  def read(uri, header={})
    request = WFO::ReqHTTP.get(uri)
    header.each {|k, v| request[k] = v }

    response = do_request(request)
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

  def read_decode(uri, header={})
    page_str = self.read(uri, header)
    unless charset = page_str.charset
      charset = page_str.guess_charset
    end
    result = page_str.decode_charset(charset)
    round_trip = result.encode_charset(charset)
    if page_str != round_trip
      raise "The locale character encoding, #{Mconv.internal_mime_charset}, cannot represent the page: #{uri}"
    end
    OpenURI::Meta.init result, page_str
    if result.respond_to? :force_encoding
      # restore encoding.  OpenURI::Meta.init set encoding accoding to charset.
      result.force_encoding(Mconv.internal_mime_charset)
    end
    return result, charset
  end

  def read_decode_nocheck(uri, header={})
    page_str = self.read(uri, header)
    unless charset = page_str.charset
      charset = page_str.guess_charset
    end
    result = page_str.decode_charset(charset)
    OpenURI::Meta.init result, page_str
    if result.respond_to? :force_encoding
      # restore encoding.  OpenURI::Meta.init set encoding accoding to charset.
      result.force_encoding(Mconv.internal_mime_charset)
    end
    return result, charset
  end
end
