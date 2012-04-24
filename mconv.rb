# mconv.rb - character code conversion library using iconv or Ruby 1.9
#
# Copyright (C) 2003-2012 Tanaka Akira  <akr@fsij.org>
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#  3. The name of the author may not be used to endorse or promote products
#     derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
# OF SUCH DAMAGE.

if !"".respond_to?(:encode)
  require 'iconv'
end

module Mconv
  def Mconv.setup(internal_mime_charset)
    if defined?(Encoding)
      @internal_mime_charset = Encoding.default_external.to_s
    else
      internal_mime_charset = internal_mime_charset.downcase
      case internal_mime_charset
      when 'euc-jp'
        kcode = 'e'
      when 'euc-kr'
        kcode = 'e'
      when 'shift_jis'
        kcode = 's'
      when 'cp932'
        kcode = 's'
      when 'iso-8859-1'
        kcode = 'n'
      when 'utf-8'
        kcode = 'u'
      else
        raise "unexpected MIME charset: #{internal_mime_charset}"
      end
      @internal_mime_charset = internal_mime_charset
      $KCODE = kcode
    end
  end

  if !defined?(Encoding)
    # xxx: euc-kr
    case $KCODE
    when /\Ae/i; @internal_mime_charset = 'euc-jp'
    when /\As/i; @internal_mime_charset = 'shift_jis'
    when /\Au/i; @internal_mime_charset = 'utf-8'
    when /\An/i; @internal_mime_charset = 'iso-8859-1'
    else
      raise "unknown $KCODE: #{$KCODE.inspect}"
    end
  end

  def Mconv.setup_locale_charset
    Mconv.setup(Mconv.locale_charset)
  end

  def Mconv.locale_charset
    codeset = Mconv.locale_codeset
    case codeset
    when /\A(?:euc-jp|eucjp|ujis)\z/i
      'euc-jp'
    when /\A(?:euc-kr|euckr)\z/i
      'euc-kr'
    when /\A(?:shift_jis|sjis)\z/i
      'shift_jis'
    when /\A(?:utf-8|utf8)\z/i
      'utf-8'
    when /\A(?:iso-8859-1|iso8859-1|us-ascii|ANSI_X3.4-1968)\z/i
      'iso-8859-1'
    else
      'utf-8'
    end
  end

  def Mconv.locale_codeset
    codeset = `locale charmap`.chomp
    status = $?
    if status.to_i == 0 && !codeset.empty?
      codeset
    else
      nil
    end
  end

  def Mconv.internal_mime_charset
    @internal_mime_charset.dup
  end

  def Mconv.valid_charset?(str)
    /\A(us-ascii|iso-2022-jp|euc-jp|shift_jis|utf-8|iso-8859-1)\z/i =~ str
  end

  def Mconv.conv(str, to, from)
    if str.respond_to? :encode
      str.encode(to, from, :invalid=>:replace, :undef=>:replace)
    else
      ic = Iconv.new(to, from)

      result = ''
      rest = str

      begin
        result << ic.iconv(rest)
      rescue Iconv::Failure
        result << $!.success

        rest = $!.failed

        # following processing should be customizable by block?
        result << '?'
        rest = rest[1..-1]

        retry
      end

      result << ic.close

      result
    end
  end

  CharsetTable = {
    'us-ascii' => /\A[\s\x21-\x7e]*\z/,
    'euc-jp' =>
      /\A(?:\s                               (?# white space character)
         | [\x21-\x7e]                       (?# ASCII)
         | [\xa1-\xfe][\xa1-\xfe]            (?# JIS X 0208)
         | \x8e(?:([\xa1-\xdf])              (?# JIS X 0201 Katakana)
                 |([\xe0-\xfe]))             (?# There is no character in E0 to FE)
         | \x8f[\xa1-\xfe][\xa1-\xfe]        (?# JIS X 0212)
         )*\z/nx,
    "iso-2022-jp" => # with katakana
      /\A[\s\x21-\x7e]*                      (?# initial ascii )
         (\e\(B[\s\x21-\x7e]*                (?# ascii )
         |\e\(J[\s\x21-\x7e]*                (?# JIS X 0201 latin )
         |\e\(I[\s\x21-\x7e]*                (?# JIS X 0201 katakana )
         |\e\$@(?:[\x21-\x7e][\x21-\x7e])*   (?# JIS X 0201 )
         |\e\$B(?:[\x21-\x7e][\x21-\x7e])*   (?# JIS X 0201 )
         )*\z/nx,
    'shift_jis' =>
      /\A(?:\s                               (?# white space character)
         | [\x21-\x7e]                       (?# JIS X 0201 Latin)
         | ([\xa1-\xdf])                     (?# JIS X 0201 Katakana)
         | [\x81-\x9f\xe0-\xef][\x40-\x7e\x80-\xfc]      (?# JIS X 0208)
         | ([\xf0-\xfc][\x40-\x7e\x80-\xfc]) (?# extended area)
         )*\z/nx,
    'utf-8' =>
      /\A(?:\s
         | [\x21-\x7e]
         | [\xc0-\xdf][\x80-\xbf]
         | [\xe0-\xef][\x80-\xbf][\x80-\xbf]
         | [\xf0-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf]
         | [\xf8-\xfb][\x80-\xbf][\x80-\xbf][\x80-\xbf][\x80-\xbf]
         | [\xfc-\xfd][\x80-\xbf][\x80-\xbf][\x80-\xbf][\x80-\xbf][\x80-\xbf]
         )*\z/nx
  }
  Preference = ['us-ascii', "iso-2022-jp", 'euc-jp', 'utf-8', 'shift_jis']

  def Mconv.guess_charset(str)
    guess_charset_list(str).first
  end

  def Mconv.guess_charset_list(str)
    if str.respond_to? :force_encoding
      str = str.dup.force_encoding("ASCII-8BIT")
    end
    case str
    when /\A\xff\xfe/; return ['utf-16le']
    when /\A\xfe\xff/; return ['utf-16be']
    end
    count = {}
    CharsetTable.each {|name, regexp|
      count[name] = 0
    }
    str.scan(/\S+/n) {|fragment|
      CharsetTable.each {|name, regexp|
        count[name] += 1 if regexp =~ fragment
      }
    }
    max = count.values.max
    count.reject! {|k, v| v != max }
    return count.keys if count.size == 1
    return ['us-ascii'] if count['us-ascii']
    
    # xxx: needs more accurate guess
    Preference.reject {|name| !count[name] }
  end

  def Mconv.minimize_charset(charset, string)
    # shortcut
    if /\A(?:euc-jp|utf-8|iso-8859-1)\z/i =~ charset
      if /\A[\x00-\x7f]*\z/ =~ string
        return 'us-ascii'
      else
        return charset
      end
    end

    charset2 = 'us-ascii'
    if string.respond_to? :encode
      begin
        # round trip?
        s2 = string.encode(charset2, charset).encode(charset, charset2)
      rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        return charset
      end
    else
      begin
        # round trip?
        s2 = Iconv.conv(charset, charset2, Iconv.conv(charset2, charset, string))
      rescue Iconv::Failure
        return charset
      end
    end
    return charset2 if string == s2
    charset
  end
end

class String
  def decode_charset(charset)
    Mconv.conv(self, Mconv.internal_mime_charset, charset)
  end

  def encode_charset(charset)
    Mconv.conv(self, charset, Mconv.internal_mime_charset)
  end

  def decode_charset_exc(charset)
    if self.respond_to? :encode
      self.encode(Mconv.internal_mime_charset, charset)
    else
      Iconv.conv(Mconv.internal_mime_charset, charset, self)
    end
  end

  def encode_charset_exc(charset)
    if self.respond_to? :encode
      self.encode(charset, Mconv.internal_mime_charset)
    else
      Iconv.conv(charset, Mconv.internal_mime_charset, self)
    end
  end

  def encode_charset_exactly(charset)
    if self.respond_to? :encode
      result = self.encode(charset, Mconv.internal_mime_charset)
      round_trip = result.encode(Mconv.internal_mime_charset, charset)
    else
      result = Iconv.conv(charset, Mconv.internal_mime_charset, self)
      round_trip = Iconv.conv(Mconv.internal_mime_charset, charset, result)
    end
    if round_trip.respond_to? :force_encoding
      round_trip.force_encoding self.encoding
    end
    if self != round_trip
      if self.length != round_trip.length
        raise ArgumentError, "not round trip (number of characters differ)"
      end
      s1 = self
      s2 = round_trip
      a1 = []; s1.each_line {|line| a1 << line }
      a2 = []; s2.each_line {|line| a2 << line }
      if a1.length != a2.length
        raise ArgumentError, "not round trip (number of lines differ)"
      end
      a1.length.times {|i|
        if a1[i] != a2[i]
          raise ArgumentError, "not round trip: #{a1[i].inspect} != #{a2[i].inspect}"
        end
      }
      raise ArgumentError, "not round trip"
    end
    result
  end

  def guess_charset
    Mconv.guess_charset(self)
  end

  def guess_charset_list
    Mconv.guess_charset_list(self)
  end

  def decode_charset_guess
    decode_charset(guess_charset)
  end
end

