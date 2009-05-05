# wfo/pat.rb - pattern library
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

module WFO
end

module WFO::Pat
  def self.disable_capture(regexp)
    re = ''
    regexp.source.scan(/\\.|[^\\\(]+|\(\?|\(/m) {|s|
      if s == '('
        re << '(?:'
      else
        re << s
      end
    }
    if regexp.respond_to? :kcode
      Regexp.new(re, regexp.options, regexp.kcode)
    else
      Regexp.new(re, regexp.options)
    end
  end

  # RFC 2616
  HTTP_Token = /[!#-'*+\-.0-9A-Z^-z|~]*/n
  HTTP_QuotedString = /"((?:[\t\r\n !#-\[\]-~]|\\[\000-\177])*)"/n

  # RFC 2617
  HTTP_AuthParam = /(#{HTTP_Token})=(#{HTTP_Token}|#{HTTP_QuotedString})/
  HTTP_Challenge = /(#{HTTP_Token})\s+(#{disable_capture HTTP_AuthParam}(?:\s*,\s*#{disable_capture HTTP_AuthParam})*)/n
  HTTP_ChallengeList = /#{HTTP_Challenge}((?:\s*,\s*#{disable_capture HTTP_Challenge})*)/n
end
