class WVS::WorkArea
  def self.has?(filename)
    n = Pathname.new(filename)
    accessor_path = n.dirname + '.wvs' + "a_#{n.basename}"
    accessor_path.exist?
  end

  def initialize(filename, accessor=nil)
    @filename = Pathname.new(filename)
    @accessor_path = @filename.dirname + '.wvs' + "a_#{@filename.basename}"
    @info_path = @filename.dirname + '.wvs' + "i_#{@filename.basename}"
    if accessor
      raise "alread exists : #{@accessor_path}" if @accessor_path.exist?
      raise "alread exists : #{@info_path}" if @info_path.exist?
      @accessor = accessor
      @info = {}
      @info['accessor_class'] = @accessor.class.to_s.sub(/^.*::/, '').downcase
    else
      raise "not exists : #{@info_path}" if !@info_path.exist?
      raise "not exists : #{@accessor_path}" if !@accessor_path.exist?
      @info_path.open('rb') {|f|
        @info = Marshal.load(f)
      }
      @accessor_path.open('rb') {|f|
        @accessor = Marshal.load(f)
      }
    end
  end
  attr_reader :filename

  def store
    @accessor_path.dirname.mkpath
    @info_path.open('wb') {|f|
      Marshal.dump(@info, f)
    }
    @accessor_path.open('wb') {|f|
      Marshal.dump(@accessor, f)
    }
    @filename.open('wb') {|f|
      f.write @accessor.current_text
    }
  end

  def modified?
    @accessor.current_text != @filename.read
  end

  def commit
    @accessor.replace_text @filename.read
    @accessor.commit
    store
  end

  def self.each_filename(dir=Pathname.new('.'))
    (dir + '.wvs').each_entry {|n|
      if /\Aa_/ =~ n.basename.to_s
        yield dir + $'
      end
    }
  end
end
