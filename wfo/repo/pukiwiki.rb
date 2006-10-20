require 'htree'

class WFO::PukiWiki < WFO::Repo
  def self.applicable?(page)
    %r{Based on "PukiWiki"} =~ page
  end

  def self.find_stable_uri(page)
    tree = HTree(page)
    tree.traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      href = e.get_attr('href')
      if href && /\?cmd=edit&/ =~ href
        return page.last_request_uri + href
      end
    }
    raise "edit page could not find : #{last_request_uri}"
  end

  def self.make_accessor(uri)
    page_str, orig_charset = WFO::WebClient.read_decode(uri)
    page_tree = HTree(page_str)
    if page_str.last_request_uri != uri
      raise "edit page redirected"
    end
    form, textarea_name, submit_name = find_textarea_form(page_tree, orig_charset)
    self.new(form, uri, textarea_name, submit_name)
  end

  def self.find_textarea_form(page, orig_charset)
    page.traverse_html_form(orig_charset) {|form|
      next unless form.input_type('write') == :submit_button
      form.each_textarea {|name, value| return form, name, 'write' }
    }
    raise "textarea not found in #{page.request_uri}"
  end

  def recommended_filename
    @uri.query.sub(/\A.*&page=/, '')
  end

  include WFO::RepoTextArea
end

__END__

def (WFO::Auth).qwik_reqauth_checker(webclient, resp)
  %r{<a href=".login"\n>Login</a\n>} =~ resp.body
end

def (WFO::Auth).qwik_auth_handler(webclient, resp)
  qwik_auth_handler_typekey(webclient, resp)
end

def (WFO::Auth).qwik_auth_handler_typekey(webclient, resp)
  uri = resp.uri
  unless %r{>powered by <a href="http://qwik.jp/"\n>qwikWeb</a} =~ resp.body
    return nil
  end
  unless %r{<a href="\.login"\n>Login</a\n>} =~ resp.body
    return nil
  end
  qwik_login_uri = uri + ".login"
  resp = webclient.do_request_state(WFO::ReqHTTP.get(qwik_login_uri))
  if resp.code == '200'
    qwik_typekey_uri = nil
    HTree(resp.body).traverse_element("{http://www.w3.org/1999/xhtml}a") {|e|
      if e.extract_text.to_s == "Login by TypeKey"
        qwik_typekey_uri = qwik_login_uri + e.get_attr('href')
      end
    }
    return nil if !qwik_typekey_uri
  elsif resp.code == '302' && %r{/\.typekey\z} =~ resp['Location']
    # "https://www.codeblog.org/.typekey"
    # "https://www.codeblog.org/wg-chairs/.typekey"
    qwik_typekey_uri = URI(resp['Location'])
  else
    return nil
  end

  resp = webclient.do_request_state(WFO::ReqHTTP.get(qwik_typekey_uri))
  return nil if resp.code != '302'
  typekey_uri = URI(resp['Location'])

  resp = WFO::Auth.typekey_login(webclient, typekey_uri)

  if resp.code == '302' # codeblog
    codeblog_uri = URI(resp['Location'])
    resp = webclient.do_request_state(WFO::ReqHTTP.get(codeblog_uri))
  end

  return nil if resp.code != '200'

  return WFO::ReqHTTP.get(uri)
end

