require 'htree'

class WVS::TDiary < WVS::Repo
  def self.applicable?(page)
    /<meta name="generator" content="tDiary/ =~ page
  end

  def self.find_stable_uri(page)
    if /<span class="adminmenu"><a href="(update.rb\?edit=true;year=\d+;month=\d+;day=\d+)">/ =~ page
      page.base_uri + $1 # it assumes base element not exist.
    elsif /<span class="adminmenu"><a href="update.rb">/ =~ page
      now = Time.now
      page.base_uri + "update.rb?edit=true;year=#{now.year};month=#{now.month};day=#{now.day}"
    else
      raise "update link not found in tDiary page : #{page.last_request_uri}"
    end
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WVS::WebClient.read_decode_nocheck(uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != uri
      raise "tDiary update page redirected"
    end
    form, textarea_name = find_replace_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name)
  end

  def self.find_replace_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      next unless form.has?('replace') && form.input_type('replace') == :submit_button
      form.each_textarea {|name, value| return form, name }
    }
    raise "replace form not found in #{page.request_uri}"
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
    req = @form.make_request('replace')
    resp = WVS::WebClient.do_request(req)
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
