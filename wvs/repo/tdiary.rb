require 'htree'

class WVS::TDiary < WVS::Repo
  def self.applicable?(page)
    /<meta name="generator" content="tDiary/ =~ page
  end

  def self.find_stable_uri(page)
    unless /<span class="adminmenu"><a href="(update.rb\?edit=true;year=\d+;month=\d+;day=\d+)">/ =~ page
      raise "update link not found in tDiary page : #{page.base_uri}"
    end
    page.base_uri + $1
  end

  def self.make_accessor(stable_uri)
    page_str = WVS::WebClient.read(stable_uri)
    page_tree = HTree(page_str)
    if page_str.base_uri != stable_uri
      raise "tDiary update page redirected"
    end
    form = find_replace_form(page_tree, stable_uri)
    self.new(form, stable_uri)
  end

  def self.find_replace_form(page, uri)
    page.traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form.traverse_element('{http://www.w3.org/1999/xhtml}input') {|input|
        if input.get_attr('type') == 'submit' &&
           input.get_attr('name') == "replace"
          return WVS::Form.make(uri, form)
        end
      }
    }
    raise "replace form not found in #{uri}"
  end

  def initialize(form, uri)
    @form = form
    @uri = uri
  end

  def current_text
    @form.fetch('body').dup
  end

  def replace_text(text)
    @form.set('body', text)
  end

  def commit
    req = @form.make_request('replace')
    req["Referer"] = @uri.to_s
    resp = WVS::WebClient.do_request(@form.action_uri, req)
    return if resp.code == '200'
    raise "HTTP POST error: #{resp.code} #{resp.message}"
  end

  def recommended_filename
    y = @form.fetch('year')
    m = @form.fetch('month')
    d = @form.fetch('day')
    "%d-%02d-%02d" % [y, m, d]
  end

  def reload
    self.class.make_accessor(@uri)
  end
end
