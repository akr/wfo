# usage:
#   wvs co [options] URL [local-filename]
#   wvs ci [options] [local-filename...]

#   wvs up [options] [local-filename...]

$KCODE = 'e'

require 'optparse'
require 'open-uri'
require 'pathname'

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
      recommended_filename = accessor.recommended_filename
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
    end
    workarea = WorkArea.new(local_filename, accessor)
    workarea.store
  end

  def make_accessor(url)
    page = url.read
    if /<meta name="generator" content="tDiary/ =~ page
      unless /<span class="adminmenu"><a href="(update.rb\?edit=true;year=(\d+);month=(\d+);day=(\d+))">/ =~ page
        err "update href not found in tDiary page."
      end
      update_url = url + $1
      year = $2
      month = $3
      day = $4
      TDiary.checkout(update_url)
    else
      err "unknown repository type : #{url}"
    end
  end

  def do_commit(argv)
    ws = []
    if argv.empty?
      WorkArea.each_filename {|n|
        ws << WorkArea.new(n)
      }
    else
      ws = argv.map {|n| WorkArea.new(n) }
    end
    ws.reject! {|w| !w.modified? }
    ws.each {|w|
      w.commit
      puts w.filename
    }
  end
end

WVS.main
