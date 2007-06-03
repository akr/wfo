# wfo/missng.rb - complement missing features
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

require 'open-uri'

unless OpenURI::Meta.instance_methods.include? "last_request_uri"
  module OpenURI::Meta
    def last_request_uri
      @base_uri
    end

    undef base_uri
    def base_uri
      if content_location = self.meta['content-location']
        u = URI(content_location)
        u = @base_uri + u if u.relative? && @base_uri
        u
      else
        @base_uri
      end
    end
  end
end

require 'htree'

unless HTree::Doc::Trav.instance_methods.include? "base_uri"
  module HTree::Doc::Trav
    attr_accessor :base_uri
  end

  alias HTree_old HTree
  def HTree(html_string=nil, &block)
    if block
      HTree_old(html_string, &block)
    else
      result = HTree_old(html_string)
      result.instance_eval {
        if html_string.respond_to? :base_uri
          @request_uri = html_string.last_request_uri
          @protocol_base_uri = html_string.base_uri
        else
          @request_uri = nil
          @protocol_base_uri = nil
        end
      }
      result
    end
  end

  module HTree::Doc::Trav
    attr_reader :request_uri

    undef base_uri
    def base_uri
      return @base_uri if defined? @base_uri
      traverse_element('{http://www.w3.org/1999/xhtml}base') {|elem|
        base_uri = URI(elem.get_attr('href'))
        base_uri = @protocol_base_uri + base_uri if @protocol_base_uri
        @base_uri = base_uri
      }
      @base_uri = @request_uri unless defined? @base_uri
      return @base_uri
    end

    def traverse_html_form(orig_charset=nil)
      traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
        yield WFO::Form.make(form, self.base_uri, @request_uri, orig_charset)
      }
      nil
    end
  end
end

unless Enumerable.instance_methods.include? "max_by"
  module Enumerable
    def max_by
      first = true
      order = nil
      value = nil
      self.each {|v|
        if first
          order = yield(v)
          value = v
          first = false
        else
          o = yield(v)
          if order < o
            order = o
            value = v
          end
        end
      }
      value
    end
  end
end

unless Enumerable.instance_methods.include? "min_by"
  module Enumerable
    def min_by
      first = true
      order = nil
      value = nil
      self.each {|v|
        if first
          order = yield(v)
          value = v
          first = false
        else
          o = yield(v)
          if o < order
            order = o
            value = v
          end
        end
      }
      value
    end
  end
end
