require 'open-uri'

unless OpenURI::Meta.instance_methods.include? "last_request_uri"
  module OpenURI::Meta
    def last_request_uri
      @base_uri
    end

    undef base_uri
    def base_uri
      if content_location = self.meta['content-location']
        u = URI(content_location)
        u = @base_uri + u if u.relative? && @base_uri
        u
      else
        @base_uri
      end
    end
  end
end

require 'htree'

unless HTree::Doc::Trav.instance_methods.include? "base_uri"
  module HTree::Doc::Trav
    attr_accessor :base_uri
  end

  alias HTree_old HTree
  def HTree(html_string=nil, &block)
    if block
      HTree_old(html_string, &block)
    else
      result = HTree_old(html_string)
      result.instance_eval {
        if html_string.respond_to? :base_uri
          @request_uri = html_string.last_request_uri
          @protocol_base_uri = html_string.base_uri
        else
          @request_uri = nil
          @protocol_base_uri = nil
        end
      }
      result
    end
  end

  module HTree::Doc::Trav
    attr_reader :request_uri

    undef base_uri
    def base_uri
      return @base_uri if defined? @base_uri
      traverse_element('{http://www.w3.org/1999/xhtml}base') {|elem|
        base_uri = URI.parse(elem.get_attr('href'))
        base_uri = @protocol_base_uri + base_uri if @protocol_base_uri
        @base_uri = base_uri
      }
      @base_uri = @request_uri unless defined? @base_uri
      return @base_uri
    end

    def traverse_html_form
      traverse_element('{http://www.w3.org/1999/xhtml}form') {|form|
        yield WVS::Form.make(form, self.base_uri, @request_uri)
      }
      nil
    end
  end
end
