# wfo/reqhttp.rb - HTTP request class
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

class WFO::ReqHTTP
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
