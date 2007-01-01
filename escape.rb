# escape.rb - escape/unescape library for several formats
#
# Copyright (C) 2006 Tanaka Akira  <akr@fsij.org>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

module Escape
  module_function

  def shell_command(command)
    command.map {|word| shell_single_word(word) }.join(' ')
  end

  def shell_single_word(str)
    if str.empty?
      "''"
    elsif %r{\A[0-9A-Za-z+,./:=@_-]+\z} =~ str
      str
    else
      result = ''
      str.scan(/('+)|[^']+/) {
        if $1
          result << %q{\'} * $1.length
        else
          result << "'#{$&}'"
        end
      }
      result
    end
  end

  def uri_segment(str)
    # pchar - pct-encoded = unreserved / sub-delims / ":" / "@"
    # unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
    # sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
    str.gsub(%r{[^A-Za-z0-9\-._~!$&'()*+,;=:@]}n) {
      '%' + $&.unpack("H2")[0].upcase
    }
  end

  def uri_path(str)
    str.gsub(%r{[^/]+}n) { uri_segment($&) }
  end

  def html_form_fast(pairs, sep=';')
    pairs.map {|k, v|
      # query-chars - pct-encoded - x-www-form-urlencoded-delimiters =
      #   unreserved / "!" / "$" / "'" / "(" / ")" / "*" / "," / ":" / "@" / "/" / "?"
      # query-char - pct-encoded = unreserved / sub-delims / ":" / "@" / "/" / "?"
      # query-char = pchar / "/" / "?" = unreserved / pct-encoded / sub-delims / ":" / "@" / "/" / "?"
      # unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
      # sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
      # x-www-form-urlencoded-delimiters = "&" / "+" / ";" / "="
      k = k.gsub(%r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n) {
        '%' + $&.unpack("H2")[0].upcase
      }
      v = v.gsub(%r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n) {
        '%' + $&.unpack("H2")[0].upcase
      }
      "#{k}=#{v}"
    }.join(sep)
  end

  def html_form(pairs, sep='&')
    r = ''
    first = true
    pairs.each {|k, v|
      # query-chars - pct-encoded - x-www-form-urlencoded-delimiters =
      #   unreserved / "!" / "$" / "'" / "(" / ")" / "*" / "," / ":" / "@" / "/" / "?"
      # query-char - pct-encoded = unreserved / sub-delims / ":" / "@" / "/" / "?"
      # query-char = pchar / "/" / "?" = unreserved / pct-encoded / sub-delims / ":" / "@" / "/" / "?"
      # unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
      # sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
      # x-www-form-urlencoded-delimiters = "&" / "+" / ";" / "="
      r << sep if !first
      first = false
      k.each_byte {|byte|
        ch = byte.chr
        if %r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n =~ ch
          r << "%" << ch.unpack("H2")[0].upcase
        else
          r << ch
        end
      }
      r << '='
      v.each_byte {|byte|
        ch = byte.chr
        if %r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n =~ ch
          r << "%" << ch.unpack("H2")[0].upcase
        else
          r << ch
        end
      }
    }
    r
  end

  HTML_TEXT_ESCAPE_HASH = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
  }
  def html_text(str)
    str.gsub(/[&<>]/) {|ch| HTML_TEXT_ESCAPE_HASH[ch] }
  end

  HTML_ATTR_ESCAPE_HASH = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;',
  }
  def html_attr(str)
    str.gsub(/[&<>"]/) {|ch| HTML_ATTR_ESCAPE_HASH[ch] }
  end

end
