# wfo/repo/textarea.rb - simple HTML textarea repository library
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

class WFO::TextArea < WFO::Repo
  def self.applicable?(page)
    %r{<textarea}i =~ page
  end

  def self.find_stable_uri(page)
    u = page.last_request_uri
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WFO::WebClient.read_decode(uri)
    page_tree = HTree(page_str)
    form, textarea_name = find_textarea_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name, nil)
  end

  def self.find_textarea_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      form.each_textarea {|name, value| return form, name }
    }
    raise "textarea not found in #{page.request_uri}"
  end

  def recommended_filename
    @form.action_uri.to_s.sub(%r{\A.*/}, '')
  end

  include WFO::RepoTextArea
end
