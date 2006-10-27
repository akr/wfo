module WFO
  module Locale
  end
end

def WFO.locale_charset
  codeset = WFO.locale_codeset
  case codeset
  when /\A(?:euc-jp|eucjp|ujis)\z/i
    'euc-jp'
  when /\A(?:euc-kr|euckr)\z/i
    'euc-kr'
  when /\A(?:shift_jis|sjis)\z/i
    'shift_jis'
  when /\A(?:utf-8|utf8)\z/i
    'utf-8'
  when /\A(?:iso-8859-1|iso8859-1)\z/i
    'iso-8859-1'
  else
    'utf-8'
  end
end

def WFO.locale_codeset
  codeset = `locale charmap`.chomp
  status = $?
  if status.to_i == 0 && !codeset.empty?
    codeset
  else
    nil
  end
end
