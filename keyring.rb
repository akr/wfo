# keyring.rb - password storage library
#
# Copyright (C) 2006,2007 Tanaka Akira  <akr@fsij.org>
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

require 'vanish'
require 'pathname'
require 'digest/sha2'
require 'escape'
autoload :Etc, 'etc'

# = keyring - manage encrypted storage for authentication information
#
# The keyring library stores authentication information such as username and
# passwords in a keyring directory in encrypted form.
#
# The keyring directory is ~/.keyring by default.
#
# gpg is used for the encryption.
#
# You needs your public and secret key for the encryption.
# (Use "gpg --gen-key" if you don't have one yet.)
#
# == How to specify your authentication information in the keyring.
#
# The keyring library uses ASCII armored gpg encrypted file to
# store passwords and related data.
#
# Comment field is used to select the file. 
#
# ~/.keyring/foobar.asc :
#   -----BEGIN PGP MESSAGE-----
#   Version: GnuPG v1.4.5 (GNU/Linux)
#   Comment: non-encrypted-prefix-of-the-strings
#
#   ... encrypted-sequence-of-strings ...
#   -----END PGP MESSAGE-----
#
# === Example 1.  TypeKey
#
# The following example stores a username and password for TypeKey.
# <http://www.sixapart.jp/typekey/>
#
#  % mkdir ~/.keyring
#  % cd ~/.keyring
#  % echo TypeKey typekey-username typekey-password |
#    gpg --comment TypeKey -e -a --default-recipient-self > typekey.asc
#
# It creates a file ~/.keyring/typekey.asc as follows.
#
#   -----BEGIN PGP MESSAGE-----
#   Version: GnuPG v1.4.5 (GNU/Linux)
#   Comment: TypeKey
#
#   ... "TypeKey typekey-username typekey-password\n" in encrypted form ...
#   -----END PGP MESSAGE-----
#
# Now, KeyRing.with_authinfo("TypeKey") {|username, password| ... }
# can be used to retrieve the typekey-username and typekey-password.
# It use gpg to decrypt the file.
# So gpg may ask you a passphrase of your key.
#
# === Example 2.  HTTP Basic Authentication
#
#  % echo http://www.example.org basic "realm" username password |
#    gpg --comment 'http://www.example.org basic "realm" username' -e -a --default-recipient-self > example-org.asc
#
# It creates a file ~/.keyring/example-org.asc as follows.
#
#   -----BEGIN PGP MESSAGE-----
#   Version: GnuPG v1.4.5 (GNU/Linux)
#   Comment: http://www.example.org basic "realm" username
#
#   ... "http://www.example.org basic "realm" username password\n" in encrypted form ...
#   -----END PGP MESSAGE-----
#
# Now, KeyRing.with_authinfo can be used to lookup username and password.
#
#   KeyRing.with_authinfo("http://www.example.org", "basic", "realm", "username") {|password| ... }
#
# It is possible to lookup username AND password as follows.
#
#   KeyRing.with_authinfo("http://www.example.org", "basic", "realm") {|username, password| ... }
#
# It is also possible to lookup realm and authentication scheme.
#
#   KeyRing.with_authinfo("http://www.example.org", "basic") {|realm, username, password| ... }
#   KeyRing.with_authinfo("http://www.example.org") {|auth_scheme, realm, username, password| ... }
#
# == Keyring Directory Layout and File Format
#
# The keyring directory is ~/.keyring.
#
# ~/.keyring may have any number of authentication information file.
# The file must be named with ".asc" suffix.
#
# The keyring library searches ~/.keyring/*.asc for authentication information.
# The filename is not important.
#
# The authentication information file should be ASCII armored gpg encrypted file as follows.
#
# ~/.keyring/foobar.asc :
#   -----BEGIN PGP MESSAGE-----
#   Version: GnuPG v1.4.5 (GNU/Linux)
#   Comment: non-encrypted-prefix
#
#   ... encrypted-sequence-of-strings ...
#   -----END PGP MESSAGE-----
#
# The file should contain Comment field and encrypted contents.
#
# The encrypted contents should be sequence of strings separated by white spaces.
# (The syntax of the strings is described later.)
#
#   Example: A B C D
#
# The Comment field should contain prefix of the sequence of strings.
#
#   Example: A B C
#   Example: A B
#   Example: A
#
# Each string in the Comment field can be a hexadecimal SHA256 hash prepended with "sha256:" prefix.
#
#   Example: sha256:559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd B
#   Example: A sha256:df7e70e5021544f4834bbee64a9e3789febc4be81470df629cad6ddb03320a5c
#   Example: sha256:559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd sha256:df7e70e5021544f4834bbee64a9e3789febc4be81470df629cad6ddb03320a5c
#
# A string contained in the Comment field and encrypted contents must be one of following forms.
#
# * A string not containing a white space and beginning with a digit or
#   alphabet.
#   /[0-9A-Za-z][!-~]*/ 
#
# * A string quoted by double quotes "...".
#   The string content may contain printable ASCII character including space
#   and escape sequences \\, \" and \xHH.
#   /"((?:[ !#-\[\]-~]|\\["\\]|\\x[0-9a-fA-F][0-9a-fA-F])*)"/
#
# * A white space is one of space, tab, newline, carriage return, form feed.
#   /\s/
#
# == Convention of Authentication Information
#
# Although the keyring library itself doesn't define the semantics of the sequence of strings, 
# it is useful to standardize the usage of the strings.
#
# So the keyring library provides convenience methods to make protection domains
# for TypeKey and HTTP Authentication.
# They returns a protection domain appropriate for an argument of KeyRing.with_authinfo.
#
# * KeyRing.typekey_protection_domain
#
#   For TypeKey authentication, protection domain is ["TypeKey"].
#   The authentication information, username and password, can be stored as follows.
#
#    % echo TypeKey typekey-username typekey-password |
#      gpg --comment TypeKey -e -a --default-recipient-self > typekey.asc
#
# * KeyRing.http_protection_domain(uri, scheme, realm)
#
#   For HTTP authentication, protection domain is [canonical-root-URL, scheme, realm].
#   In Basic authentication, "basic" is used for the scheme.
#
#   The Basic authentication information, username and password, can be stored as follows.
#
#    % echo 'canonical-root-url basic "realm" username password' |
#      gpg --comment 'canonical-root-URL basic "realm"' -e -a --default-recipient-self > service.asc
#
# === Method
#
# * KeyRing.with_authinfo(protection_domain) {|authentication_informaion| ... }
# * KeyRing.typekey_protection_domain
# * KeyRing.http_protection_domain(uri, scheme, realm)
#

class KeyRing
  # KeyRing.with_authinfo takes one or more strings as the argument.
  # protection_domain can be a string or an array of strings.
  #
  # protection_domain is compared to the Comment fields in ~/.keyring/*.asc.
  # If a matched Comment field is found, the corresponding file is decrypted to obtain
  # the authentication information represented as a sequence of strings using gpg.
  #
  # KeyRing.with_authinfo yields the sequence of strings excluded with
  # beginning words given with protection_domain.
  #
  def self.with_authinfo(protection_domain, &block) # :yields: authentication_information
    self.new.with_authinfo(protection_domain, &block)
  end

  # :stopdoc:

  def self.decrypt_file(path)
    `#{Escape.shell_command(%W[gpg -d -q #{path}])}`
  end

  def initialize(dir=nil)
    unless dir
      home = ENV['HOME'] || Etc.getpwuid.dir
      dir = "#{home}/.keyring"
    end
    @dir = Pathname.new(dir)
  end

  def with_authinfo(protection_domain) # :yield: password
    protection_domain = [protection_domain] if String === protection_domain
    path = search_encrypted_file(protection_domain)
    s = KeyRing.decrypt_file(path)
    if $? != 0
      s.vanish!
      raise AuthInfoNotFound, "gpg failed with #{$?}"
    end
    begin
      authinfo = KeyRing.decode_strings_safe(s)
      s.vanish!
      s = nil
      if protection_domain.length <= authinfo.length &&
         authinfo[0, protection_domain.length] == protection_domain
        authinfo[0, protection_domain.length].each {|v| v.vanish! }
        authinfo[0, protection_domain.length] = []
      end
      ret = yield *authinfo
    ensure
      s.vanish! if s
      authinfo.each {|v| v.vanish! } if authinfo
    end
    ret
  end

  def match_protection_domain(given, spec)
    given == spec ||
    (/\Asha256:/ =~ spec && $' == Digest::SHA256.hexdigest(given))
  end

  def search_encrypted_file(protection_domain)
    paths = @dir.children.sort_by {|path| path.to_s }
    paths.each {|path|
      next if path.extname != '.asc'
      path.each_line {|line|
        break if line == "\n"
        if /^Comment:/ =~ line
          prefix = KeyRing.decode_strings($')
          next if prefix.length < protection_domain.length
          if protection_domain.zip(prefix).all? {|s, t| match_protection_domain(s, t) }
            return path
          end
        end
      }
    }
    raise AuthInfoNotFound, "authentication information not found in #{@dir}: #{KeyRing.encode_strings protection_domain}" 
  end

  # :startdoc:

  class AuthInfoNotFound < StandardError
  end

  # KeyRing.typekey_protection_domain returns ["TypeKey"].
  def self.typekey_protection_domain
    ["TypeKey"]
  end

  # KeyRing.http_protection_domain returns [canonical-root-URL-of-given-uri, scheme, realm]
  def self.http_protection_domain(uri, scheme, realm)
    uri = uri.dup
    # make it canonical root URL
    uri.path = ""
    uri.query = nil
    uri.fragment = nil
    [uri.to_s, scheme, realm]
  end

  # :stopdoc:

  def self.encode_strings(strings)
    strings.map {|s|
      if /\A[0-9A-Za-z][!-~]*\z/ =~ s
        s
      else
        '"' +
        s.gsub(/[^ !#-\[\]-~]/n) {|ch|
          case ch
          when /["\\]/
            '\\' + ch
          else
            '\x' + ch.unpack("H2")[0]
          end
        } +
        '"'
      end
    }.join(' ')
  end

  RawStrPat = /[0-9A-Za-z][!-~]*/ 
  QuotedStrPat = /"((?:[ !#-\[\]-~]|\\["\\]|\\x[0-9a-fA-F][0-9a-fA-F])*)"/
  def self.decode_strings(str)
    s = str
    r = []
    until /\A\s*\z/ =~ s
      case s
      when /\A\s*(#{RawStrPat})(?:\s+|\z)/o
        s = $'
        r << $1
      when /\A\s*(#{QuotedStrPat})(?:\s+|\z)/o
        s = $'
        r << $2.gsub(/\\(["\\])|\\x([0-9a-fA-F][0-9a-fA-F])/) { $1 || [$2].pack("H2") }
      else
        raise ArgumentError, "strings syntax error: #{str.inspect}"
      end
    end
    r
  end

  Spaces = [?\s, ?\n, ?\t]

  # KeyRing.decode_strings_safe is same as KeyRing.decode_strings except
  # it doesn't retain temporally strings which contains a part of the argument.
  # Single character strings may retains, though.
  def self.decode_strings_safe(str)
    r = []
    i = 0
    len = str.length
    while i < len
      ch = str[i]
      i += 1
      next if Spaces.include? ch
      case ch
      when ?0..?9, ?A..?Z, ?a..?z
        s = ch.chr
        r << s
        while i < len && !Spaces.include?(str[i])
          s << str[i].chr
          i += 1
        end
      when ?"
        s = ""
        r << s
        while true
          raise ArgumentError, "strings syntax error" if i == len
          ch = str[i]
          i += 1
          if ?" === ch
            break
          elsif ?\\ === ch
            if i < len
              ch = str[i]
              i += 1
              case ch
              when ?", ?\\
                s << ch.chr
              when ?x
                if i+1 < len
                  ch1 = str[i]
                  raise ArgumentError, "strings syntax error" if /\A[0-9a-fA-F]\z/n !~ ch1.chr
                  ch2 = str[i+1]
                  raise ArgumentError, "strings syntax error" if /\A[0-9a-fA-F]\z/n !~ ch2.chr
                  s << (ch1.chr.to_i(16) * 16 + ch2.chr.to_i(16)).chr
                  i += 2
                else
                  raise ArgumentError, "strings syntax error"
                end
              else
                raise ArgumentError, "strings syntax error"
              end
            else
              raise ArgumentError, "strings syntax error"
            end
          elsif /\A[\s!#-\[\]-~]\z/ =~ ch.chr
            s << ch.chr
          else
            raise ArgumentError, "strings syntax error"
          end
        end
        if i < len && !Spaces.include?(str[i])
          raise ArgumentError, "strings syntax error"
        end
      else
        raise ArgumentError, "strings syntax error"
      end
    end
    r
  ensure
    if $!
      r.each {|s| s.vanish! }
    end
  end

  # :startdoc:
end
