class WVS::WebClient
  def self.do
    webclient = self.new
    old = Thread.current[:webclient]
    begin
      Thread.current[:webclient] = webclient
      yield
    ensure
      Thread.current[:webclient] = old
    end
  end

  def self.read(uri, opts={})
    Thread.current[:webclient].read(uri, opts)
  end

  def initialize
  end

  def read(uri, opts={})
    uri.read(opts)
  end
end
