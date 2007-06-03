# wfo/auth.rb - authentication library
#
# Copyright (C) 2006 Tanaka Akira  <akr@fsij.org>
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

module WFO::Auth
  @reqauth_checker = []
  @auth_handler = []

  def self.added(name)
    name = name.to_s
    if /_reqauth_checker\z/ =~ name
      @reqauth_checker << method(name)
    elsif /_auth_handler\z/ =~ name
      @auth_handler << method(name)
    end
  end
end

class << WFO::Auth
  attr_reader :reqauth_checker
  attr_reader :auth_handler

  def singleton_method_added(name)
    WFO::Auth.added(name)
  end
end

module WFO::Auth
  def self.codeblog_auth_handler(webclient, response)
    uri = response.uri
    unless response.code == '403' &&
           ((uri.scheme == 'https' && uri.host == 'www.codeblog.org' && uri.port == 443) ||
            (uri.scheme == 'http' && uri.host == 'vv.codeblog.org' && uri.port == 80))
      return nil
    end
    apache_authtypekey_handler(webclient, response)
  end

  def self.apache_authtypekey_handler(webclient, response)
    uri = response.uri
    errpage = response.body
    return nil if />(Please login|Log in) via TypeKey</ !~ errpage
    # It seems a login page generated by login.pl in Apache-AuthTypeKey.
    typekey_uri = nil
    HTree(errpage).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      if href = e.get_attr('href')
        href = URI(href)
        if href.host == 'www.typekey.com'
          typekey_uri = href
          break
        end
      end
    }
    return nil if !typekey_uri

    response = typekey_login(webclient, typekey_uri)
    return nil if response.code != '302'
    #destination_uri = URI(resp['Location'])

    # use uri instead of destination_uri because www.codeblog.org's login.pl
    # had a URI escaping problem.

    return WFO::ReqHTTP.get(uri)
  end

  def self.typekey_login(webclient, typekey_uri)
    typekey_login_form = nil
    HTree(typekey_uri).traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form = WFO::Form.make(form, typekey_uri)
      if form.has?('username') && form.has?('password')
        typekey_login_form = form
        break
      end
    }
    return nil if !typekey_login_form
    resp = nil
    KeyRing.with_authinfo(KeyRing.typekey_protection_domain) {|username, password|
      typekey_login_form.set('username', username)
      typekey_login_form.set('password', password)
      typekey_login_form.make_request {|req|
        resp = webclient.do_request_state(req)
      }
    }
    # The password vanishing is not perfect, unfortunately.
    # arr = []; ObjectSpace.each_object(String) {|s| arr << s }; arr.each {|v| p v }

    if resp.code == '200' # send email address or not?
      email_form = nil
      HTree(resp.body).traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
        email_form = WFO::Form.make(form, typekey_login_form.action_uri)
        break
      }
      req = email_form.make_request
      resp = webclient.do_request_state(req)
    end

    return nil if resp.code != '302'
    return_uri = URI(resp['Location'])

    webclient.do_request_state(WFO::ReqHTTP.get(return_uri))
  end
end

module WFO
  def Auth.http_auth_basic(webclient, response, params)
    uri = response.uri
    return nil if params.size != 1
    k, v = params.shift
    return nil if /\Arealm\z/i !~ k
    realm = v
    protection_domain = KeyRing.http_protection_domain(uri, 'basic', realm)
    canonical_root_url = protection_domain[0]
    KeyRing.with_authinfo(protection_domain) {|username, password|
      user_pass = "#{username}:#{password}"
      credential = [user_pass].pack("m")
      KeyRing.vanish!(user_pass)
      credential.gsub!(/\s+/, '')
      path_pat = /\A#{Regexp.quote uri.path.sub(%r{[^/]*\z}, '')}/
      webclient.add_basic_credential(canonical_root_url, realm, path_pat, credential)
    }
    return response.request
  end

  def Auth.http_auth_digest(webclient, response, params)
    realm = params['realm']
    nonce = params['nonce']
    qop = params['qop']
    algorithm = params['algorithm'] || 'MD5'
    opaque = params['opaque']

    return nil if !realm
    return nil if !nonce
    return nil if qop != 'auth'
    return nil if /\Amd5\z/i !~ algorithm

    canonical_root_url = response.uri.dup
    canonical_root_url.path = ""
    canonical_root_url.query = nil
    canonical_root_url.fragment = nil
    if domain = params['domain']
      domain_uris = domain.split(/\s+/)
      protection_domain_uris = domain_uris.map {|u|
        u = URI.parse(u)
        u = canonical_root_url + u if u.relative?
        u
      }
    else
      protection_domain_uris = [canonical_root_url]
    end
    target_host_protection_domain_uris =  protection_domain_uris.reject {|u|
      u.scheme != canonical_root_url.scheme ||
      u.host != canonical_root_url.host ||
      u.port != canonical_root_url.port
    }
    target_host_protection_domain_uris = [canonical_root_url] if target_host_protection_domain_uris.empty?
    shortest_uri = target_host_protection_domain_uris.min_by {|u| u.path.length }
    protection_domain = [shortest_uri.to_s, 'digest', realm]
    KeyRing.with_authinfo(protection_domain) {|username, password|
      a1 = "#{username}:#{realm}:#{password}"
      ha1 = Digest::MD5.hexdigest(a1)
      KeyRing.vanish!(a1)
      webclient.add_digest_credential(protection_domain_uris, realm, username.dup, nonce, ha1, algorithm, opaque)
    }
    return response.request
  end

  HTTPAuthSchemeStrength = {
    'basic' => 1,
    'digest' => 2,
  }
  HTTPAuthSchemeStrength.default = -1
    
  def Auth.http_auth_handler(webclient, response)
    unless response.code == '401' &&
           response['www-authenticate'] &&
           response['www-authenticate'] =~ /\A\s*#{Pat::HTTP_ChallengeList}s*\z/n
      return nil
    end
    challenges = [[$1, $2]]
    rest = $3
    challenges.concat rest.scan(/\s*,\s*#{Pat::HTTP_Challenge}/)
    challenges.map! {|as, r|
      params = {}
      while /\A#{Pat::HTTP_AuthParam}(?:(?:\s*,\s*)|\s*\z)/ =~ r
        r = $'
        k = $1
        v = $3 ? $3.gsub(/\\([\000-\377])/) { $1 } : $2
        return nil if params[k]
        params[k] = v
      end
      [as.downcase, params]
    }
    challenge = challenges.max_by {|as, _| HTTPAuthSchemeStrength[as] }

    auth_scheme, params = challenge
    return nil if HTTPAuthSchemeStrength[auth_scheme] < 0

    self.send("http_auth_#{auth_scheme}", webclient, response, params)
  end
end

