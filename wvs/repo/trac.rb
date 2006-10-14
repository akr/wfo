require 'htree'

class WVS::Trac < WVS::Repo
  def self.applicable?(page)
    %r{<a id="tracpowered" href="http://trac.edgewall.com/">} =~ page
  end

  def self.find_stable_uri(page)
    u = page.last_request_uri.dup
    u.query = 'action=edit'
    u
  end

  def self.make_accessor(edit_uri)
    page_str = WVS::WebClient.read(edit_uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != edit_uri
      raise "Trac edit page redirected"
    end
    form, textarea_name = find_textarea_form(page_tree, page_tree.base_uri, page_str.last_request_uri)
    self.new(form, edit_uri, textarea_name)
  end

  def self.find_textarea_form(page, base_uri, referer_uri)
    page.traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
      form.traverse_element('{http://www.w3.org/1999/xhtml}textarea') {|textarea|
        return WVS::Form.make(form, base_uri, referer_uri), textarea.get_attr('name')
      }
    }
    raise "textarea not found in #{uri}"
  end

  def initialize(form, uri, textarea_name)
    @form = form
    @uri = uri
    @textarea_name = textarea_name
  end

  def current_text
    @form.fetch(@textarea_name).dup
  end

  def replace_text(text)
    @form.set(@textarea_name, text)
  end

  def commit
    req = @form.make_request('save')
    req["Referer"] = @uri.to_s
    resp = WVS::WebClient.do_request(@form.action_uri, req)
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

def (WVS::Auth).trac_auth_handler(webclient, uri, req, resp)
  unless %r{<a id="tracpowered" href="http://trac.edgewall.com/">} =~ resp.body
    return nil
  end
  if resp.code != '403'
    return nil
  end

  trac_login_uri = nil
  HTree(resp.body).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
    if e.extract_text.to_s == "Login"
      trac_login_uri = uri + e.get_attr('href')
      break
    end
  }
  return nil if !trac_login_uri
  webclient.read(trac_login_uri)

  return uri, req
end

