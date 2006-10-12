# = keyring - manage authentication information in encrypted form.
#
# The keyring library stores authentication information such as username and passwords
# in a keyring directory in encrypted form.
#
# The keyring directory is ~/.keyring by default.
#
# gpg is used for the encryption.
#
# You needs your public and secret key for the encryption.
# (Use "gpg --gen-key" if you don't have it yet.)
#
# == How to specify your authentication information in the keyring.
#
# The following example stores a username and password for TypeKey.
# <http://www.sixapart.jp/typekey/>
#
# % mkdir ~/.keyring
# % cd ~/.keyring
# % (echo typekey-username typekey-password) | gpg --comment TypeKey -e -a --default-recipient-self > typekey.asc
#
# It creates a file ~/.keyring/typekey.asc as follows.
#
#   -----BEGIN PGP MESSAGE-----
#   Version: GnuPG v1.4.5 (GNU/Linux)
#   Comment: TypeKey
#
#   ... encrypted data ...
#   -----END PGP MESSAGE-----
#
# Now, KeyRing.with_authinfo("TypeKey") {|username, password| ... }
# can be used to retriev the username and password.
# It use gpg to decrypt the file.
# So gpg may ask you a passphrase of your key.
#
# KeyRing.with_authinfo searches *.asc in the keyring directory and
# examine a Comment field in them.
# So the library finds an appropriate encrypted file regardless of filenames.

require 'vanish'
require 'pathname'
require 'escape'
autoload :Etc, 'etc'

class KeyRing
  def self.with_authinfo(protection_domain, &block)
    self.new.with_authinfo(protection_domain, &block)
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
    s = `#{Escape.shell_command(%W[gpg -d -q --no-tty #{path}])}`
    begin
      authinfo = KeyRing.decode_strings_safe(s)
      s.vanish!
      s = nil
      ret = yield *authinfo
    ensure
      s.vanish! if s
      authinfo.each {|v| v.vanish! } if authinfo
    end
    ret
  end

  def search_encrypted_file(protection_domain)
    paths = @dir.children.sort_by {|path| path.to_s }
    paths.each {|path|
      next if path.extname != '.asc'
      path.each_line {|line|
        break if line == "\n"
        if /^Comment:/ =~ line
          return path if KeyRing.decode_strings($') == protection_domain
        end
      }
    }
    raise "authentication information not found in #{@dir}: #{KeyRing.encode_strings protection_domain}" 
  end

  def self.typekey_protection_domain
    ["TypeKey"]
  end

  def self.http_protection_domain(uri, realm)
    uri = uri.dup
    # make it canonical root URL
    uri.path = ""
    uri.query = nil
    uri.fragment = nil
    [uri.to_s, realm]
  end

  def self.encode_strings(strings)
    strings.map {|s|
      if /\A[0-9A-Za-z][!-~]*\z/ =~ s
        s
      else
        '"' +
        s.gsub(/[^!#-\[\]-~]/n) {|ch|
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
  QuotedStrPat = /"((?:[!#-\[\]-~]|\\["\\]|\\x[0-9a-fA-F][0-9a-fA-F])*)"/
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
        raise "strings syntax error: #{str.inspect}"
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
          raise "strings syntax error" if i == len
          ch = str[i]
          i += 1
          case ch
          when ?"
            break
          when ?\\
            if i < len
              ch = str[i]
              i += 1
              case ch
              when ?", ?\\
                s << ch.chr
              when ?x
                if i+1 < len
                  ch1 = str[i]
                  raise "strings syntax error" if /\A[0-9a-fA-F]\z/n !~ ch1.chr
                  ch2 = str[i+1]
                  raise "strings syntax error" if /\A[0-9a-fA-F]\z/n !~ ch2.chr
                  s << (ch1.chr.to_i(16) * 16 + ch2.chr.to_i(16)).chr
                else
                  raise "strings syntax error"
                end
              else
                raise "strings syntax error"
              end
            else
              raise "strings syntax error"
            end
          else
            s << ch.chr
          end
        end
        if i < len && !Spaces.include?(str[i])
          raise "strings syntax error"
        end
      else
        raise "strings syntax error"
      end
    end
    r
  ensure
    if $!
      r.each {|s| s.vanish! }
    end
  end

end
