# wfo/resphttp.rb - HTTP response class
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

class WFO::RespHTTP
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
