module Escape
  module_function

  def shell_escape(str)
    if str.empty?
      "''"
    elsif %r{\A[0-9A-Za-z+,./:=@_-]+\z} =~ str
      str
    else
      result = ''
      str.scan(/('+)|[^']+/) {
        if $1
          result << %q{\'} * $1.length
        else
          result << "'#{$&}'"
        end
      }
      result
    end
  end

  def html_form(pairs, sep=';')
    pairs.map {|k, v|
      # query chars - x-www-form-urlencoded delimiters
      # query chars: unreserved / sub-delims / "/" / ":" / "?" / "@"
      # unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
      # sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
      # x-www-form-urlencoded delimiters: "&" / "+" / ";" / "="
      k = k.gsub(%r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}) {
        '%' + $&.unpack("H2")[0].upcase
      }
      v = v.gsub(%r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}) {
        '%' + $&.unpack("H2")[0].upcase
      }
      "#{k}=#{v}"
    }.join(sep)
  end
end
