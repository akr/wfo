module WVS
end

module WVS::Pat
  # RFC 2616
  HTTP_Token = /[!#-'*+\-.0-9A-Z^-z|~]*/n
  HTTP_QuotedString = /"((?:[\t\r\n !#-\[\]-~]|\\[\000-\177])*)"/n

  # RFC 2617
  HTTP_AuthParam = /(#{HTTP_Token})=(#{HTTP_Token}|#{HTTP_QuotedString})/
  HTTP_Challenge = /(#{HTTP_Token})\s+(#{HTTP_AuthParam}(?:\s*,\s*#{HTTP_AuthParam})*)/n
end
