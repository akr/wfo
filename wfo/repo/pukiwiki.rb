# wfo/repo/pukiwiki.rb - PukiWiki repository library
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

require 'htree'

class WFO::PukiWiki < WFO::Repo
  def self.applicable?(page)
    %r{Based on "PukiWiki"} =~ page
  end

  def self.find_stable_uri(page)
    tree = HTree(page)
    tree.traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      href = e.get_attr('href')
      if href && /\?cmd=edit&/ =~ href
        return page.last_request_uri + href
      end
    }
    raise "edit page could not find : #{last_request_uri}"
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WFO::WebClient.read_decode(uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != uri
      raise "edit page redirected"
    end
    form, textarea_name, submit_name = find_textarea_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name, submit_name)
  end

  def self.find_textarea_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      next unless form.input_type('write') == :submit_button
      form.each_textarea {|name, value| return form, name, 'write' }
    }
    raise "textarea not found in #{page.request_uri}"
  end

  def recommended_filename
    @uri.query.sub(/\A.*&page=/, '')
  end

  include WFO::RepoTextArea
end
