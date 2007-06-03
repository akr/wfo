# wfo/repo/trac.rb - Trac's Wiki repository library
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

require 'htree'

class WFO::Trac < WFO::Repo
  def self.applicable?(page)
    %r{<a id="tracpowered" href="http://trac.edgewall.(com|org)/">} =~ page
  end

  def self.find_stable_uri(page)
    u = page.last_request_uri.dup
    u.query = 'action=edit'
    u
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WFO::WebClient.read_decode(uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != uri
      raise "Trac edit page redirected"
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
    @form.action_uri.to_s.sub(%r{\A.*/}, '')
  end

  include WFO::RepoTextArea
end

module WFO::Auth
  def self.trac_auth_handler(webclient, resp)
    uri = resp.uri

    unless %r{<a id="tracpowered" href="http://trac.edgewall.(com|org)/">} =~ resp.body
      return nil
    end
    if resp.code != '403'
      return nil
    end

    trac_login_uri = nil
    HTree(resp.body).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      if e.extract_text.to_s == "Login"
        trac_login_uri = uri + e.get_attr('href')
        break
      end
    }
    return nil if !trac_login_uri
    webclient.read(trac_login_uri)

    return WFO::ReqHTTP.get(uri)
  end
end
