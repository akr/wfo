# wfo/repo/qwik.rb - qwikWeb repository library
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

require 'htree'

class WFO::Qwik < WFO::Repo
  def self.applicable?(page)
    %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ page
  end

  def self.find_stable_uri(page)
    last_request_uri = page.last_request_uri.to_s
    if /\.html\z/ =~ last_request_uri
      return URI(last_request_uri.sub(/\.html\z/, '.edit'))
    else
      tree = HTree(page)
      tree.traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
        href = e.get_attr('href')
        if href && /\.edit\z/ =~ href
          return page.last_request_uri + href
        end
      }
    end
    raise "edit page could not find : #{last_request_uri}"
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WFO::WebClient.read_decode(uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != uri
      raise "qwikWeb edit page redirected"
    end
    form, textarea_name, submit_name = find_textarea_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name, submit_name)
  end

  def self.find_textarea_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      next unless form.input_type('save') == :submit_button
      form.each_textarea {|name, value| return form, name, 'save' }
    }
    raise "textarea not found in #{page.request_uri}"
  end

  def recommended_filename
    @form.action_uri.to_s.sub(%r{\A.*/}, '').sub(/\.save\z/, '')
  end

  include WFO::RepoTextArea
end

module WFO::Auth
  def self.qwik_reqauth_checker(webclient, resp)
    if %r{<a href=".login"\n>Login</a\n>} !~ resp.body
      return nil
    end
    lambda { qwik_auth_handler(webclient, resp) }
  end

  def self.qwik_auth_handler(webclient, resp)
    qwik_auth_handler_typekey(webclient, resp)
  end

  def self.qwik_auth_handler_typekey(webclient, resp)
    uri = resp.uri
    unless %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ resp.body
      return nil
    end
    unless %r{<a href="\.login"\n>Login</a\n>} =~ resp.body
      return nil
    end
    qwik_login_uri = uri + ".login"
    resp = webclient.do_request_state(WFO::ReqHTTP.get(qwik_login_uri))
    qwik_typekey_uri = nil
    qwik_basicauth_uri = nil
    if resp.code == '200'
      HTree(resp.body).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
        if e.extract_text.to_s == "Log in by Basic Authentication."
          qwik_basicauth_uri = qwik_login_uri + e.get_attr('href')
        end
        if e.extract_text.to_s == "Login by TypeKey" ||
           e.extract_text.to_s == "Log in by TypeKey"
          qwik_typekey_uri = qwik_login_uri + e.get_attr('href')
        end
      }
    elsif resp.code == '302' && %r{/\.typekey\z} =~ resp['Location']
      # "https://www.codeblog.org/.typekey"
      # "https://www.codeblog.org/wg-chairs/.typekey"
      qwik_typekey_uri = URI(resp['Location'])
    end

    if qwik_basicauth_uri
      webclient.do_request(WFO::ReqHTTP.get(qwik_basicauth_uri))
      return WFO::ReqHTTP.get(uri)
    end

    if qwik_typekey_uri
      resp = webclient.do_request_state(WFO::ReqHTTP.get(qwik_typekey_uri))
      return nil if resp.code != '302'
      typekey_uri = URI(resp['Location'])

      resp = WFO::Auth.typekey_login(webclient, typekey_uri)

      if resp.code == '302' # codeblog
        codeblog_uri = URI(resp['Location'])
        resp = webclient.do_request_state(WFO::ReqHTTP.get(codeblog_uri))
      end

      return nil if resp.code != '200'

      return WFO::ReqHTTP.get(uri)
    end

    nil
  end
end
