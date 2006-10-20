class WFO::Repo
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

  def self.find_class_and_stable_uri(url, type=nil)
    page = WFO::WebClient.read(url)
    if type
      c = fetch_class(type)
      stable_uri = c.find_stable_uri(page)
      return c, stable_uri
    else
      @repo_classes.each {|c|
        if c.applicable?(page)
          stable_uri = c.find_stable_uri(page)
          return c, stable_uri
        end
      }
    end
    raise "unknown repository type : #{url}"
  end

  def self.make_accessor(url, type=nil)
    c, stable_uri = find_class_and_stable_uri(url, type)
    return c.make_accessor(stable_uri)
  end
end

module WFO::RepoTextArea
  def initialize(form, uri, textarea_name, submit_name)
    @form = form
    @uri = uri
    @textarea_name = textarea_name
    @submit_name = submit_name
  end
  attr_reader :form, :textarea_name

  def current_text
    @form.fetch(@textarea_name).dup
  end

  def replace_text(text)
    @form.set(@textarea_name, text)
  end

  def commit
    req = @form.make_request(@submit_name)
    resp = WFO::WebClient.do_request(req)
    return if resp.code == '200'
    raise "HTTP POST error: #{resp.code} #{resp.message}"
  end

  def reload
    self.class.make_accessor(@uri)
  end
end

