module WFO
end

class WFO::Cookie
  AttrPat = /[^=;,]+/
  QuotedStringPat = /"[\r\n\t !#-\377]*"/
  ObsValuePat = /[A-Za-z]{3}, \d\d-[A-Za-z]{3}-\d\d(?:\d\d+)? \d\d:\d\d:\d\d GMT/
  ValuePat = /#{ObsValuePat}|#{QuotedStringPat}|[^;,]*/

  def self.parse(request_uri, field_value)
    self.split(field_value).map {|pairs|
      self.new(request_uri, pairs)
    }

  end

  def self.split(field_value)
    cookies = [[]]
    field_value.scan(/(#{AttrPat})\s*(?:=\s*(#{ValuePat})\s*)?([;,])?/) {|attr, value, term|
      attr = attr.strip
      cookies.last << [attr, value]
      if term == ','
        cookies << []
      end
    }
    cookies.pop if cookies.last == []
    cookies
  end

  def initialize(request_uri, pairs)
    @request_uri = request_uri
    @pairs = pairs
    pair = @pairs.find {|k, v| /\Adomain\z/i =~ k }
    if !pair
      @domain = request_uri.host
      @domain_pat = /\A#{Regexp.quote @domain}\z/i
    else
      cookie_domain = pair[1]
      if /\A\./ !~ cookie_domain
        raise ArgumentError, "An cookie domain not started with a dot: #{cookie_domain}"
      end
      if /\..*\./ !~ cookie_domain
        raise ArgumentError, "An cookie domain needs more dots: #{cookie_domain}"
      end
      if /#{Regexp.quote cookie_domain}\z/ !~ request_uri.host
        raise ArgumentError, "An cookie domain is not match: #{cookie_domain} is not suffix of #{request_uri.host}"
      end
      @domain = cookie_domain
      @domain_pat = /#{Regexp.quote cookie_domain}\z/i
    end
    pair = @pairs.find {|k, v| /\Apath\z/i =~ k }
    if !pair
      @path = request_uri.path.sub(%r{[^/]*\z}, '')
      @path_pat = /\A#{Regexp.quote @path}/
    else
      cookie_path = pair[1]
      sep = %r{/\z} =~ cookie_path ? "" : '(\z|/)'
      if %r{\A#{Regexp.quote cookie_path}#{sep}} !~ request_uri.path
        raise ArgumentError, "An cookie path is not match: #{cookie_path} is not prefix of #{request_uri.path}"
      end
      @path = cookie_path
      @path_pat = /\A#{Regexp.quote cookie_path}#{sep}/
    end
  end
  attr_reader :domain, :path

  def match?(uri)
    return false if @domain_pat !~ uri.host
    return false if @path_pat !~ uri.path
    return false if @pairs.find {|k, v| /\Asecure\z/ =~ k } && uri.scheme != 'https'
    true
  end

  def name
    @pairs[0][0]
  end

  def value
    @pairs[0][1]
  end

  def encode_cookie_field
    name, value = @pairs[0]
    "#{name}=#{value}"
  end
end
