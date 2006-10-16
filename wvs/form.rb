require 'vanish'
require 'escape'
require 'net/https'

module WVS
end

class WVS::Form
  def self.make(form_tree, base_uri, referer_uri=nil, orig_charset=nil)
    action_uri = base_uri + form_tree.get_attr('action')
    method = form_tree.get_attr('method')
    enctype = form_tree.get_attr('enctype')
    accept_charset = form_tree.get_attr('accept-charset')
    form = self.new(action_uri, method, enctype, accept_charset, referer_uri, orig_charset)
    form_tree.traverse_element(
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
          form.add_text(name, control.get_attr('value').to_s)
        when 'hidden'
          form.add_hidden(name, control.get_attr('value').to_s)
        when 'password'
          form.add_password(name, control.get_attr('value').to_s)
        when 'submit'
          form.add_submit_button(name, control.get_attr('value').to_s)
        when 'checkbox'
          checked = control.get_attr('checked') ? :checked : nil
          form.add_checkbox(name, control.get_attr('value').to_s, checked)
        when 'radio'
          checked = control.get_attr('checked') ? :checked : nil
          form.add_radio(name, control.get_attr('value').to_s, checked)
        when 'file'
          form.add_file(name)
        else
          raise "unexpected input type : #{type}"
        end
      when '{http://www.w3.org/1999/xhtml}button'
        next if control.get_attr('disabled')
        raise "unexpected control : #{control.name}"
      when '{http://www.w3.org/1999/xhtml}select'
        next if control.get_attr('disabled')
        multiple = control.get_attr('multiple') ? :multiple : nil
        options = []
        control.traverse_element('{http://www.w3.org/1999/xhtml}option') {|option|
          next if option.get_attr('disabled')
          selected = option.get_attr('selected') ? :selected : nil
          options << [selected, option.get_attr('value')]
        }
        form.add_select(name, multiple, options)
      when '{http://www.w3.org/1999/xhtml}textarea'
        next if control.get_attr('disabled')
        form.add_textarea(name, control.extract_text.to_s)
      else
        raise "unexpected control : #{control.name}"
      end
    }
    form
  end

  def initialize(action_uri, method=nil, enctype=nil, accept_charset=nil, referer_uri=nil, orig_charset=nil)
    @action_uri = action_uri
    method ||= 'get'
    @method = method.downcase
    enctype ||= 'application/x-www-form-urlencoded'
    @enctype = enctype.downcase
    if accept_charset
      @accept_charset = accept_charset.downcase.split(/\s+/)
    elsif orig_charset
      @accept_charset = [orig_charset]
    else
      @accept_charset = ['utf-8']
    end
    @accept_charset.map! {|charset| charset.downcase }
    @controls = []
    @referer_uri = referer_uri
  end
  attr_reader :action_uri, :referer_uri

  def add_text(name, value)
    @controls << [name, value, :text]
  end

  def add_hidden(name, value)
    @controls << [name, value, :hidden]
  end

  def add_password(name, value)
    @controls << [name, value, :password]
  end

  def add_submit_button(name, value)
    @controls << [name, value, :submit_button]
  end

  def add_checkbox(name, value, checked)
    @controls << [name, value, :checkbox, checked]
  end

  def add_radio(name, value, checked)
    @controls << [name, value, :radio, checked]
  end

  def add_file(name)
    @controls << [name, nil, :file]
  end

  def add_select(name, multiple, options)
    @controls << [name, options, :select, multiple]
  end

  def add_textarea(name, value)
    @controls << [name, value, :textarea]
  end

  def set(name, value)
    c = @controls.assoc(name)
    raise IndexError, "no control : #{name}" if !c
    c[1] = value
  end

  def fetch(name)
    c = @controls.assoc(name)
    raise IndexError, "no control : #{name}" if !c
    return c[1]
  end

  def input_type(name)
    c = @controls.assoc(name)
    raise IndexError, "no control : #{name}" if !c
    return c[2]
  end

  def get(name)
    c = @controls.assoc(name)
    return nil if !c
    return c[1]
  end

  def has?(name)
    c = @controls.assoc(name)
    !!c
  end

  def each_textarea
    @controls.each {|name, value, type|
      if type == :textarea
        yield name, value
      end
    }
  end

  def make_request(submit_name=nil)
    secrets = []
    case @method
    when 'get'
      case @enctype
      when 'application/x-www-form-urlencoded'
        query = encode_application_x_www_form_urlencoded(submit_name)
        secrets << query
        request_uri = @action_uri.request_uri + "?"
        request_uri += query
        secrets << request_uri
        req = Net::HTTP::Get.new(@action_uri.request_uri + "?" + query)
      else
        raise "unexpected enctype: #{@enctype}"
      end
    when 'post'
      case @enctype
      when 'application/x-www-form-urlencoded'
        query = encode_application_x_www_form_urlencoded(submit_name)
        secrets << query
        req = Net::HTTP::Post.new(@action_uri.request_uri)
        req.body = query
        req['Content-Type'] = 'application/x-www-form-urlencoded'
      else
        raise "unexpected enctype: #{@enctype}"
      end
    else
      raise "unexpected method: #{@method}"
    end
    if @referer_uri
      req['Referer'] = @referer_uri.to_s
    end
    if block_given?
      begin
        yield req
      ensure
        secrets.each {|s|
          s.vanish!
        }
      end
    else
      req
    end
  end

  def encode_application_x_www_form_urlencoded(submit_name=nil)
    successful = []
    has_submit = false
    @controls.each {|name, value, type, *rest|
      case type
      when :submit_button
        if !has_submit && name == submit_name
          successful << [name, value]
          has_submit = true
        end
      when :checkbox, :radio
        checked = rest[0]
        successful << [name, value] if checked
      when :text, :textarea, :password, :hidden
        successful << [name, value]
      when :select
        selected_options = []
        value.each {|selected, option| selected_options << option if selected }
        selected_options.each {|option| successful << [name, option] }
      else
        raise "unexpected control type: #{type}"
      end
    }
    accept_charset = @accept_charset.dup
    charset = accept_charset.shift
    begin
      encoded_successful = successful.map! {|name, value|
        [name.encode_charset_exc(charset), value.encode_charset_exc(charset)]
      }
    rescue Iconv::Failure
      if charset = accept_charset.shift
        retry
      else
        encoded_successful = successful
      end
    end
    Escape.html_form(encoded_successful)
  end
end
