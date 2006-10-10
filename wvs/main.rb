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
      local_filename = make_local_filename(accessor.recommended_filename)
    end
    workarea = WorkArea.new(local_filename, accessor)
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

  def make_accessor(url)
    page = url.read
    if ret = TDiary.checkout_if_possible(page)
      ret
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
