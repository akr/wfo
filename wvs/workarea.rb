require 'zlib'

class WVS::WorkArea
  def self.has?(filename)
    n = Pathname.new(filename)
    info_path = n.dirname + '.wvs' + "i_#{n.basename}.gz"
    info_path.exist?
  end

  def initialize(filename, repository_type=nil, url=nil, original_text=nil, form=nil)
    @filename = Pathname.new(filename)
    @info_path = @filename.dirname + '.wvs' + "i_#{@filename.basename}.gz"
    if url
      raise "alread exists : #{@info_path}" if @info_path.exist?
      @url = url.dup
      @info = {}
      @info['URL'] = @url
      @info['repository_type'] = repository_type.dup
      @info['original_text'] = original_text.dup
      @info['form'] = form
    else
      raise "not exists : #{@info_path}" if !@info_path.exist?
      Zlib::GzipReader.open(@info_path) {|f|
        @info = Marshal.load(f)
      }
      @url = @info['URL']
    end
  end
  attr_reader :filename, :url

  def make_accessor
    WVS::Repo.fetch_class(@info['repository_type']).make_accessor(@info['URL'])
  end

  def store
    store_info
    store_text
  end

  def store_info
    @info_path.dirname.mkpath
    Zlib::GzipWriter.open(@info_path) {|f|
      Marshal.dump(@info, f)
    }
  end

  def store_text
    @filename.open('wb') {|f|
      f.write self.original_text
    }
  end

  def original_text
    @info['original_text']
  end

  def original_text=(text)
    @info['original_text'] = text
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

  def self.each_filename(dir=Pathname.new('.'))
    (dir + '.wvs').each_entry {|n|
      if /\Ai_(.*)\.gz\z/ =~ n.basename.to_s
        yield dir + $1
      end
    }
  end
end
