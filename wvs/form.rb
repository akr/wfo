require 'vanish'
require 'escape'
require 'net/https'

class WVS::Form
  def self.make(base_uri, form_tree)
    action_uri = base_uri + form_tree.get_attr('action')
    method = form_tree.get_attr('method')
    enctype = form_tree.get_attr('enctype')
    form = self.new(action_uri, method, enctype)
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
        else
          raise "unexpected input type : #{type}"
        end
      when '{http://www.w3.org/1999/xhtml}button'
        next if control.get_attr('disabled')
      when '{http://www.w3.org/1999/xhtml}select'
        next if control.get_attr('disabled')
      when '{http://www.w3.org/1999/xhtml}textarea'
        next if control.get_attr('disabled')
        form.add_textarea(name, control.extract_text.to_s)
      else
        raise "unexpected control : #{control.name}"
      end
    }
    form
  end

  def initialize(action_uri, method=nil, enctype=nil)
    @action_uri = action_uri
    method ||= 'get'
    @method = method.downcase
    enctype ||= 'application/x-www-form-urlencoded'
    @enctype = enctype.downcase
    @controls = []
  end
  attr_reader :action_uri

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

  def get(name)
    c = @controls.assoc(name)
    return nil if !c
    return c[1]
  end

  def has?(name)
    c = @controls.assoc(name)
    !!c
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
      when :checkbox
        checked = rest[0]
        successful << [name, value] if checked
      when :text, :textarea, :password, :hidden
        successful << [name, value]
      else
        raise "unexpected control type: #{type}"
      end
    }
    Escape.html_form(successful)
  end
end
