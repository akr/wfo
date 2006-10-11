class WVS::Repo
  @repo_classes = []

  def self.inherited(subclass)
    @repo_classes << subclass
  end

  def self.repo_classes
    @repo_classes
  end

  def self.type
    self.to_s.sub(/\A.*::/, '').downcase
  end

  def self.available_types
    @repo_classes.map {|c| c.type }
  end

  def self.fetch_class(type)
    @repo_classes.each {|c|
      return c if c.type == type
    }
    raise "repository class not found: #{type}"
  end

  def self.make_accessor(url, type=nil)
    page = WVS::WebClient.read(url)
    if type
      c = fetch_class(type)
      return c.try_checkout(page)
    else
      @repo_classes.each {|c|
        if ret = c.checkout_if_possible(page)
          return ret 
        end
      }
    end
    raise "unknown repository type : #{url}"
  end

end
