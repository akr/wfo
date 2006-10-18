require 'htree'

class WVS::TextArea < WVS::Repo
  def self.applicable?(page)
    %r{<textarea}i =~ page
  end

  def self.find_stable_uri(page)
    u = page.last_request_uri
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WVS::WebClient.read_decode(uri)
    page_tree = HTree(page_str)
    form, textarea_name = find_textarea_form(page_tree, page_tree.base_uri, page_str.last_request_uri, orig_charset)
    self.new(form, uri, textarea_name)
  end

  def self.find_textarea_form(page, base_uri, referer_uri, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      form.each_textarea {|name, value| return form, name } 
    }
    raise "textarea not found in #{referer_uri}"
  end

  def initialize(form, uri, textarea_name)
    @form = form
    @uri = uri
    @textarea_name = textarea_name
  end
  attr_reader :form, :textarea_name

  def current_text
    @form.fetch(@textarea_name).dup
  end

  def replace_text(text)
    @form.set(@textarea_name, text)
  end

  def commit
    req = @form.make_request
    resp = WVS::WebClient.do_request(req)
    return if resp.code == '200'
    raise "HTTP POST error: #{resp.code} #{resp.message}"
  end

  def recommended_filename
    @form.action_uri.to_s.sub(%r{\A.*/}, '')
  end

  def reload
    self.class.make_accessor(@uri)
  end
end
