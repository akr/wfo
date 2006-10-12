require 'htree'
require 'escape'
require 'net/http'

class WVS::TDiary < WVS::Repo
  def self.checkout_if_possible(page)
    if /<meta name="generator" content="tDiary/ =~ page
      try_checkout(page)
    else
      nil
    end
  end

  def self.try_checkout(page)
    unless /<span class="adminmenu"><a href="(update.rb\?edit=true;year=(\d+);month=(\d+);day=(\d+))">/ =~ page
      raise "update href not found in tDiary page : #{url}"
    end
    update_url = page.base_uri + $1
    year = $2
    month = $3
    day = $4
    self.checkout(update_url)
  end

  def self.checkout(update_url)
    update_page_str = WVS::WebClient.read(update_url)
    update_page_tree = HTree(update_page_str)
    form = find_replace_form(update_page_tree, update_url)
    form = WVS::Form.make(update_page_str.base_uri, form)
    self.new(form, update_url, update_page_str.base_uri)
  end

  def self.find_replace_form(page, uri)
    page.traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form.traverse_element('{http://www.w3.org/1999/xhtml}input') {|input|
        if input.get_attr('type') == 'submit' &&
           input.get_attr('name') == "replace"
          return form
        end
      }
    }
    raise "replace form not found in #{uri}"
  end

  def initialize(form, update_url, referer)
    @form = form
    @update_url = update_url
    @referer = referer
  end

  def current_text
    @form.fetch('body').dup
  end

  def replace_text(text)
    @form.set('body', text)
  end

  def commit
    req = @form.make_request('replace')
    req["Referer"] = @referer.to_s
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
    self.class.checkout(@update_url)
  end
end
