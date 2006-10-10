# usage:
#   wvs co [options] URL [local-filename]
#   wvs st [options] [local-filename...]
#   wvs up [options] [local-filename...]
#   wvs ci [options] [local-filename...]

$KCODE = 'e'

require 'optparse'
require 'open-uri'
require 'pathname'
require 'tempfile'

module WVS
end

require 'wvs/workarea'

require 'wvs/repo/tdiary'

module WVS
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
    when 'commit', 'ci'
      do_commit ARGV
    else
      err "unknown subcommand : #{subcommand}"
    end
  end

  def do_checkout(argv)
    url = URI(argv.shift)
    local_filename = argv.shift
    if local_filename && WorkArea.has?(local_filename)
      err "local file already exists : #{local_filename.inspect}"
    end
    accessor = make_accessor(url)
    if !local_filename
      local_filename = make_local_filename(accessor.recommended_filename)
    end
    workarea = WorkArea.new(local_filename, url, accessor.current_text)
    workarea.store
  end

  def make_local_filename(recommended_filename)
    if !WorkArea.has?(recommended_filename)
      local_filename = recommended_filename
    else
      n = 1
      begin
        tmp = "#{recommended_filename}_#{n}"
        n += 1
      end while WorkArea.has?(tmp)
      local_filename = tmp
    end
    local_filename
  end

  def do_status(argv)
    ws = argv_to_workareas(argv)
    ws.each {|w|
      accessor = make_accessor(w.url)
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
  end

  def do_update(argv)
    ws = argv_to_workareas(argv)
    ws.each {|w|
      accessor = make_accessor(w.url)
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
  end

  def merge(local_text, original_text, remote_text)
    original_file = Tempfile.new("wvs.original")
    original_file.write original_text
    original_file.flush
    local_file = Tempfile.new("wvs.local")
    local_file.write local_text
    local_file.flush
    remote_file = Tempfile.new("wvs.remote")
    remote_file.write remote_text
    remote_file.flush
    merged = IO.popen(Escape.shell_command(['diff3', '-mE', '-L', 'edited by you', '-L', 'before edited', '-L', 'edited by others', local_file.path, original_file.path, remote_file.path]), 'r') {|f|
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
    ws = argv_to_workareas(argv)
    ws.reject! {|w| !w.modified? }
    up_to_date = true
    as = []
    ws.each {|w|
      accessor = make_accessor(w.url)
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

  def make_accessor(url)
    page = url.read
    if ret = TDiary.checkout_if_possible(page)
      ret
    else
      err "unknown repository type : #{url}"
    end
  end

end

WVS.main
