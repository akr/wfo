# wfo/repo/tdiary.rb - tDiary repository library
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

class WFO::TDiary < WFO::Repo
  def self.applicable?(page)
    /<meta name="generator" content="tDiary/ =~ page
  end

  def self.find_stable_uri(page)
    if /<span class="adminmenu"><a href="(update.rb\?edit=true;year=\d+;month=\d+;day=\d+)">/ =~ page
      page.base_uri + $1 # it assumes base element not exist.
    elsif /<span class="adminmenu"><a href="update.rb">/ =~ page
      now = Time.now
      page.base_uri + "update.rb?edit=true;year=#{now.year};month=#{now.month};day=#{now.day}"
    else
      raise "update link not found in tDiary page : #{page.last_request_uri}"
    end
  end

  def self.make_accessor(uri, version)
    page_str, orig_charset = WFO::WebClient.read_decode_nocheck(uri, veirfy)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != uri
      raise "tDiary update page redirected"
    end
    form, textarea_name, submit_name = find_replace_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name, submit_name)
  end

  def self.find_replace_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      next unless form.input_type('replace') == :submit_button
      form.each_textarea {|name, value| return form, name, 'replace' }
    }
    raise "replace form not found in #{page.request_uri}"
  end

  def recommended_filename
    y = @form.fetch('year')
    m = @form.fetch('month')
    d = @form.fetch('day')
    "%d-%02d-%02d" % [y, m, d]
  end

  include WFO::RepoTextArea
end
