class WVS::WorkArea
  def self.has?(filename)
    n = Pathname.new(filename)
    info_path = n.dirname + '.wvs' + "i_#{n.basename}"
    info_path.exist?
  end

  def initialize(filename, url=nil, original_text=nil)
    @filename = Pathname.new(filename)
    @info_path = @filename.dirname + '.wvs' + "i_#{@filename.basename}"
    if url
      raise "alread exists : #{@info_path}" if @info_path.exist?
      @url = url.dup
      @info = {}
      @info['URL'] = @url
      @info['original_text'] = original_text
    else
      raise "not exists : #{@info_path}" if !@info_path.exist?
      @info_path.open('rb') {|f|
        @info = Marshal.load(f)
      }
      @url = @info['URL']
    end
  end
  attr_reader :filename, :url

  def store
    store_info
    store_text
  end

  def store_info
    @info_path.dirname.mkpath
    @info_path.open('wb') {|f|
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

  def modified?
    self.original_text != self.local_text
  end

  def self.each_filename(dir=Pathname.new('.'))
    (dir + '.wvs').each_entry {|n|
      if /\Ai_/ =~ n.basename.to_s
        yield dir + $'
      end
    }
  end
end
