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

module WFO
class WorkArea
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

  def self.checkout(url, local_filename_arg=nil, repo_type=nil)
    if !local_filename_arg
      extname = '.txt'
    elsif /^\./ =~ local_filename_arg
      extname = local_filename_arg
    else
      if /\./ =~ local_filename_arg
        local_filename = local_filename_arg
      else
        local_filename = local_filename_arg + '.txt'
      end
      if WorkArea.has?(local_filename)
        err "local file already exists : #{local_filename.inspect}"
      end
    end
    repo_class, stable_uri = Repo.find_class_and_stable_uri(url, repo_type)
    accessor = repo_class.make_accessor(stable_uri)

    if !local_filename
      local_filename = make_local_filename(accessor.recommended_filename, extname)
    end
    workarea = WorkArea.new(local_filename, accessor.class.type, stable_uri, accessor.form, accessor.textarea_name)
    workarea.store
    local_filename
  end

  def self.make_local_filename(recommended_basename, extname)
    if %r{/} =~ recommended_basename ||
      recommended_basename = File.basename(recommended_basename)
    end
    if recommended_basename.empty?
      recommended_basename = "empty-filename"
    end
    tmp = "#{recommended_basename}#{extname}"
    if !WorkArea.has?(tmp)
      local_filename = tmp
    else
      n = 1
      begin
        tmp = "#{recommended_basename}_#{n}#{extname}"
        n += 1
      end while WorkArea.has?(tmp)
      local_filename = tmp
    end
    local_filename
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

  def update
    accessor = self.make_accessor
    remote_text = accessor.current_text
    local_text = self.local_text
    original_text = self.original_text
    if original_text != remote_text
      if original_text == local_text
        self.local_text = remote_text
        self.original_text = remote_text
        self.store_info
        puts "#{self.filename}: updated"
      else 
        merged, conflict = merge(local_text, original_text, remote_text)
        backup_path = self.make_backup(local_text)
        self.local_text = merged
        self.original_text = remote_text
        self.store_info
        if conflict
          puts "#{self.filename}: conflict (backup: #{backup_path})"
        else
          puts "#{self.filename}: merged (backup: #{backup_path})"
        end
      end
    end

  end

  def merge(local_text, original_text, remote_text)
    original_file = tempfile("wfo.original", original_text)
    local_file = tempfile("wfo.local", local_text)
    remote_file = tempfile("wfo.remote", remote_text)
    command = ['diff3', '-mE',
      '-L', 'edited by you',
      '-L', 'before edited',
      '-L', 'edited by others',
      local_file.path,
      original_file.path,
      remote_file.path]
    merged = IO.popen(Escape.shell_command(command), 'r') {|f|
      f.read
    }
    status = $?
    unless status.exited?
      raise "[bug] unexpected diff3 failure: #{status.inspect}"
    end
    case status.exitstatus
    when 0
      conflict = false
    when 1
      conflict = true
    when 2
      raise "diff3 failed"
    else
      raise "[bug] unexpected diff3 status: #{status.inspect}"
    end
    return merged, conflict
  end

  def tempfile(basename, content)
    t = Tempfile.new(basename)
    t.write content
    t.flush
    t
  end

end
end
