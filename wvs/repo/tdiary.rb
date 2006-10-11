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
    page_url = update_page_str.base_uri
    update_page = HTree(update_page_str)
    form = find_replace_form(update_page)
    submit_url = update_url + form.get_attr('action')
    submit_method = form.get_attr('method') || 'get'
    submit_method = submit_method.downcase
    submit_enctype = form.get_attr('enctype') || 'application/x-www-form-urlencoded'
    submit_enctype = submit_enctype.downcase
    referer = update_url
    successful = successful_controls(form)
    self.new(update_url, submit_url, submit_method, submit_enctype, referer, successful)
  end

  def self.find_replace_form(page)
    page.traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form.traverse_element('{http://www.w3.org/1999/xhtml}input') {|input|
        if input.get_attr('type') == 'submit' &&
           input.get_attr('name') == "replace"
          return form
        end
      }
    }
    raise "replace form not found in #{page.base_url}"
  end

  def self.successful_controls(form)
    controls = extract_controls(form)
    successful = []
    has_submit = false
    controls.each {|type, name, value, *rest|
      case type
      when :submit_button
        if !has_submit && name == 'replace'
          successful << [name, value]
          has_submit = true
        end
      when :checkbox
        checked = rest[0]
        successful << [name, value] if checked
      when :hidden, :text
        successful << [name, value]
      else
        raise "unexpected control type: #{type}"
      end
    }
    successful
  end

  def self.extract_controls(form)
    result = []
    form.traverse_element(
      '{http://www.w3.org/1999/xhtml}input',
      '{http://www.w3.org/1999/xhtml}button',
      '{http://www.w3.org/1999/xhtml}select',
      '{http://www.w3.org/1999/xhtml}textarea') {|control|
      name = control.get_attr('name')
      next if !name
      case control.name
      when '{http://www.w3.org/1999/xhtml}input'
        next if control.get_attr('disabled')
        type = control.get_attr('type')
        type = type ? type.downcase : 'text'
        case type
        when 'text'
          result << [:text, name, control.get_attr('value').to_s]
        when 'hidden'
          result << [:hidden, name, control.get_attr('value').to_s]
        when 'submit'
          result << [:submit_button, name, control.get_attr('value').to_s]
        when 'checkbox'
          checked = control.get_attr('checked') ? :checked : nil
          result << [:checkbox, name, control.get_attr('value').to_s, checked]
        else
          raise "unexpected input type : #{type}"
        end
      when '{http://www.w3.org/1999/xhtml}button'
        next if control.get_attr('disabled')
      when '{http://www.w3.org/1999/xhtml}select'
        next if control.get_attr('disabled')
      when '{http://www.w3.org/1999/xhtml}textarea'
        next if control.get_attr('disabled')
        result << [:text, name, control.extract_text.to_s]
      else
        raise "unexpected control : #{control.name}"
      end
    }
    result
  end

  def initialize(update_url, submit_url, submit_method, submit_enctype, referer, controls)
    @update_url = update_url
    @submit_url = submit_url
    @submit_method = submit_method
    @submit_enctype = submit_enctype
    @referer = referer
    @controls = controls
  end

  def current_text
    @controls.assoc('body')[1].dup
  end

  def replace_text(text)
    @controls.assoc('body')[1] = text
  end

  def commit
    raise "unexpected method: #{@submit_method} (POST expected)" if @submit_method != 'post'
    raise "unexpected enctype: #{@submit_enctype} (application/x-www-form-urlencoded expected)" if @submit_enctype != 'application/x-www-form-urlencoded'
    header = {
      'Referer' => @referer.to_s,
      'Content-Type' => 'application/x-www-form-urlencoded; charset=EUC-JP'
    }
    Net::HTTP.start(@submit_url.host, @submit_url.port) {|http|
      resp = http.post(@submit_url.request_uri, Escape.html_form(@controls), "Referer"=>@referer.to_s)
      return if resp.code == '200'
      raise "HTTP POST error: #{resp.code} resp.message"
    }
  end

  def recommended_filename
    y = @controls.assoc('year')[1]
    m = @controls.assoc('month')[1]
    d = @controls.assoc('day')[1]
    "#{y}-#{m}-#{d}"
  end

  def reload
    self.class.checkout(@update_url)
  end
end
