# usage:
#   wfo checkout [-t repo_type] URL [local-filename][.ext]
#   wfo status [-u] [local-filename...]
#   wfo update [local-filename...]
#   wfo commit [local-filename...]
#   wfo diff [-u] [local-filename...]
#   wfo workdump [local-filename...]

require 'mconv'

require 'optparse'
require 'open-uri'
require 'pathname'
require 'tempfile'

module WFO
end

require 'wfo/missing'
require 'wfo/pat'

require 'wfo/workarea'
require 'wfo/webclient'

require 'wfo/repo'
require 'wfo/repo/tdiary'
require 'wfo/repo/qwik'
require 'wfo/repo/trac'
require 'wfo/repo/pukiwiki'

require 'wfo/repo/textarea'

module WFO
  module_function

  def err(msg)
    STDERR.puts msg
    exit 1
  end

  def main
    subcommand = ARGV.shift
    case subcommand
    when 'checkout', 'co'
      do_checkout ARGV
    when 'status', 'stat', 'st'
      do_status ARGV
    when 'update', 'up'
      do_update ARGV
    when 'commit', 'checkin', 'ci'
      do_commit ARGV
    when 'diff', 'di'
      do_diff ARGV
    when 'workdump'
      do_workdump ARGV
    else
      err "unknown subcommand : #{subcommand}"
    end
  end

  def do_checkout(argv)
    opt = OptionParser.new
    opt.banner = 'Usage: wfo checkout [-t repo_type] URL [local-filename]'
    opt_t = nil; opt.def_option('-t repo_type', "repository type (#{Repo.available_types})") {|v|
      opt_t = v
    }
    opt.def_option('-h', 'help') { puts opt; exit 0 }
    opt.parse!(argv)
    WebClient.do {
      url = URI(argv.shift)
      local_filename_arg = argv.shift
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
      repo_class, stable_uri = Repo.find_class_and_stable_uri(url, opt_t)
      accessor = repo_class.make_accessor(stable_uri)

      if !local_filename
        local_filename = make_local_filename(accessor.recommended_filename, extname)
      end
      workarea = WorkArea.new(local_filename, accessor.class.type, stable_uri, accessor.form, accessor.textarea_name)
      workarea.store
      puts local_filename
    }
  end

  def make_local_filename(recommended_basename, extname)
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

  def do_status(argv)
    opt = OptionParser.new
    opt.banner = 'Usage: wfo status [options] [local-filename...]'
    opt_u = false; opt.def_option('-u', 'update check') { opt_u = true }
    opt.def_option('-h', 'help') { puts opt; exit 0 }
    opt.parse!(argv)
    WebClient.do {
      ws = argv_to_workareas(argv)
      if opt_u
        ws.each {|w|
          accessor = w.make_accessor
          remote_text = accessor.current_text
          local_text = w.local_text
          original_text = w.original_text
          if original_text == local_text
            if original_text == remote_text
              # not interesting.
            else
              puts "#{w.filename}: needs-update"
            end
          else
            if original_text == remote_text
              puts "#{w.filename}: localy-modified"
            else
              puts "#{w.filename}: needs-merge"
            end
          end
        }
      else
        ws.each {|w|
          local_text = w.local_text
          original_text = w.original_text
          if original_text != local_text
            puts "#{w.filename}: localy-modified"
          end
        }
      end
    }
  end

  def do_update(argv)
    WebClient.do {
      ws = argv_to_workareas(argv)
      ws.each {|w|
        accessor = w.make_accessor
        remote_text = accessor.current_text
        local_text = w.local_text
        original_text = w.original_text
        if original_text != remote_text
          if original_text == local_text
            w.local_text = remote_text
            w.original_text = remote_text
            w.store_info
            puts "#{w.filename}: updated"
          else
            merged, conflict = merge(local_text, original_text, remote_text)
            backup_path = w.make_backup(local_text)
            w.local_text = merged
            w.original_text = remote_text
            w.store_info
            if conflict
              puts "#{w.filename}: conflict (backup: #{backup_path})"
            else
              puts "#{w.filename}: merged (backup: #{backup_path})"
            end
          end
        end
      }
    }
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

  def do_commit(argv)
    WebClient.do {
      ws = argv_to_workareas(argv)
      ws.reject! {|w| !w.modified? }
      up_to_date = true
      as = []
      ws.each {|w|
        accessor = w.make_accessor
        remote_text = accessor.current_text
        local_text = w.local_text
        original_text = w.original_text
        if remote_text != original_text
          puts "not up-to-date : #{w.filename}"
          up_to_date = false
        end
        as << [w, accessor, local_text]
      }
      exit 1 if !up_to_date
      as.each {|w, accessor, local_text|
        accessor.replace_text local_text
        accessor.commit
        accessor2 = accessor.reload
        if accessor2.current_text != local_text
          backup_filename = w.make_backup(local_text)
          puts "commited not exactly.  local file backup: #{backup_filename}"
          w.local_text = accessor2.current_text
          w.original_text = accessor2.current_text
          w.store
        else
          w.original_text = local_text
          w.store_info
        end
        puts w.filename
      }
    }
  end

  def do_diff(argv)
    opt = OptionParser.new
    opt.banner = 'Usage: wfo diff [options] [local-filename...]'
    opt_u = false; opt.def_option('-u', 'update check') { opt_u = true }
    opt.def_option('-h', 'help') { puts opt; exit 0 }
    opt.parse!(argv)
    WebClient.do {
      ws = argv_to_workareas(argv)
      no_diff = true
      ws.each {|w|
        local_text = w.local_text
        if opt_u
          accessor = w.make_accessor
          other_text = accessor.current_text
          other_label = "#{w.filename} (remote)"
        else
          other_text = w.original_text
          other_label = "#{w.filename} (original)"
        end
        if other_text != local_text
          no_diff = false
          other_file = tempfile("wfo.other", other_text)
          local_file = tempfile("wfo.local", local_text)
          command = ['diff', '-u',
            "--label=#{other_label}", other_file.path,
            "--label=#{w.filename}", local_file.path]
          system(Escape.shell_command(command))
        end
      }
      exit no_diff
    }
  end

  def do_workdump(argv)
    argv.each {|n|
      puts "#{n} :"
      pp WorkArea.new(n).instance_eval { @info }
    }
  end

  def argv_to_workareas(argv)
    ws = []
    if argv.empty?
      WorkArea.each_filename {|n|
        ws << WorkArea.new(n)
      }
    else
      ws = argv.map {|n| WorkArea.new(n) }
    end
    ws
  end

  def tempfile(basename, content)
    t = Tempfile.new(basename)
    t.write content
    t.flush
    t
  end

end

WFO.main
