# wfo/workarea.rb - local workarea library
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

require 'zlib'

class WFO::WorkArea
  def self.has?(filename)
    n = Pathname.new(filename)
    info_path = n.dirname + '.wfo' + "i_#{n.basename}.gz"
    info_path.exist?
  end

  def self.each_filename(dir=Pathname.new('.'))
    (dir + '.wfo').each_entry {|n|
      if /\Ai_(.*)\.gz\z/ =~ n.basename.to_s
        yield dir + $1
      end
    }
  end

  def initialize(filename, repository_type=nil, url=nil, form=nil, textarea_name=nil)
    @filename = Pathname.new(filename)
    @info_path = @filename.dirname + '.wfo' + "i_#{@filename.basename}.gz"
    if url
      raise "alread exists : #{@info_path}" if @info_path.exist?
      @url = url.dup
      @info = {}
      @info['URL'] = @url
      @info['repository_type'] = repository_type.dup
      @info['form'] = form
      @info['textarea_name'] = textarea_name
    else
      raise "not exists : #{@info_path}" if !@info_path.exist?
      Zlib::GzipReader.open(@info_path.to_s) {|f|
        @info = Marshal.load(f)
      }
      @url = @info['URL']
    end
  end
  attr_reader :filename, :url

  def make_accessor
    WFO::Repo.fetch_class(@info['repository_type']).make_accessor(@info['URL'])
  end

  def store
    store_info
    store_text
  end

  def store_info
    @info_path.dirname.mkpath
    Zlib::GzipWriter.open(@info_path.to_s) {|f|
      Marshal.dump(@info, f)
    }
  end

  def store_text
    @filename.open('wb') {|f|
      f.write self.original_text
    }
  end

  def original_text
    @info['form'].fetch(@info['textarea_name'])
  end

  def original_text=(text)
    @info['form'].set(@info['textarea_name'], text)
  end

  def local_text
    @filename.open('rb') {|f| f.read }
  end

  def local_text=(text)
    @filename.open('wb') {|f| f.write text }
  end

  def make_backup(text)
    backup_filename = @filename.dirname + (".~" + @filename.basename.to_s)
    backup_filename.open("wb") {|f| f.write text }
    backup_filename
  end

  def modified?
    self.original_text != self.local_text
  end

end
