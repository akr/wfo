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
    form, textarea_name = find_textarea_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name, nil)
  end

  def self.find_textarea_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      form.each_textarea {|name, value| return form, name }
    }
    raise "textarea not found in #{page.request_uri}"
  end

  def recommended_filename
    @form.action_uri.to_s.sub(%r{\A.*/}, '')
  end

  include WVS::RepoTextArea
end
