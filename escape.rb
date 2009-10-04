# escape.rb - escape/unescape library for several formats
#
# Copyright (C) 2006,2007,2009 Tanaka Akira  <akr@fsij.org>
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#  3. The name of the author may not be used to endorse or promote products
#     derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
# OF SUCH DAMAGE.

# Escape module provides several escape functions.
# * URI
# * HTML
# * shell command
# * MIME parameter
module Escape
  module_function

  class StringWrapper
    class << self
      alias new_no_dup new
      def new(str)
        new_no_dup(str.dup)
      end
    end

    def initialize(str)
      @str = str
    end

    def escaped_string
      @str.dup
    end

    alias to_s escaped_string

    def inspect
      "\#<#{self.class}: #{@str}>"
    end

    def ==(other)
      other.class == self.class && @str == other.instance_variable_get(:@str)
    end
    alias eql? ==

    def hash
      @str.hash
    end
  end

  class ShellEscaped < StringWrapper
  end

  # Escape.shell_command composes
  # a sequence of words to
  # a single shell command line.
  # All shell meta characters are quoted and
  # the words are concatenated with interleaving space.
  # It returns an instance of ShellEscaped.
  #
  #  Escape.shell_command(["ls", "/"]) #=> #<Escape::ShellEscaped: ls />
  #  Escape.shell_command(["echo", "*"]) #=> #<Escape::ShellEscaped: echo '*'>
  #
  # Note that system(*command) and
  # system(Escape.shell_command(command).to_s) is roughly same.
  # There are two exception as follows.
  # * The first is that the later may invokes /bin/sh.
  # * The second is an interpretation of an array with only one element: 
  #   the element is parsed by the shell with the former but
  #   it is recognized as single word with the later.
  #   For example, system(*["echo foo"]) invokes echo command with an argument "foo".
  #   But system(Escape.shell_command(["echo foo"]).to_s) invokes "echo foo" command
  #   without arguments (and it probably fails).
  def shell_command(command)
    s = command.map {|word| shell_single_word(word) }.join(' ')
    ShellEscaped.new_no_dup(s)
  end

  # Escape.shell_single_word quotes shell meta characters.
  # It returns an instance of ShellEscaped.
  #
  # The result string is always single shell word, even if
  # the argument is "".
  # Escape.shell_single_word("") returns #<Escape::ShellEscaped: ''>.
  #
  #  Escape.shell_single_word("") #=> #<Escape::ShellEscaped: ''>
  #  Escape.shell_single_word("foo") #=> #<Escape::ShellEscaped: foo>
  #  Escape.shell_single_word("*") #=> #<Escape::ShellEscaped: '*'>
  def shell_single_word(str)
    if str.empty?
      ShellEscaped.new_no_dup("''")
    elsif %r{\A[0-9A-Za-z+,./:=@_-]+\z} =~ str
      ShellEscaped.new(str)
    else
      result = ''
      str.scan(/('+)|[^']+/) {
        if $1
          result << %q{\'} * $1.length
        else
          result << "'#{$&}'"
        end
      }
      ShellEscaped.new_no_dup(result)
    end
  end

  class InvalidHTMLForm < StandardError
  end
  class PercentEncoded < StringWrapper
    # Escape::PercentEncoded#split_html_form decodes
    # percent-encoded string as
    # application/x-www-form-urlencoded
    # defined by HTML specification.
    #
    # It recognizes "&" and ";" as a separator of key-value pairs.
    #
    # If it find is not valid as
    # application/x-www-form-urlencoded,
    # Escape::InvalidHTMLForm exception is raised.
    #
    #  Escape::PercentEncoded.new("a=b&c=d")
    #  #=> [[#<Escape::PercentEncoded: a>, #<Escape::PercentEncoded: b>],
    #       [#<Escape::PercentEncoded: c>, #<Escape::PercentEncoded: d>]]
    #
    #  Escape::PercentEncoded.new("a=b;c=d").split_html_form
    #  #=> [[#<Escape::PercentEncoded: a>, #<Escape::PercentEncoded: b>],
    #       [#<Escape::PercentEncoded: c>, #<Escape::PercentEncoded: d>]]
    #
    #  Escape::PercentEncoded.new("%3D=%3F").split_html_form
    #  #=> [[#<Escape::PercentEncoded: %3D>, #<Escape::PercentEncoded: %3F>]]
    #
    def split_html_form
      assoc = []
      @str.split(/[&;]/, -1).each {|s|
        raise InvalidHTMLForm, "invalid: #{@str}" unless /=/ =~ s
        assoc << [PercentEncoded.new_no_dup($`), PercentEncoded.new_no_dup($')]
      }
      assoc
    end
  end

  # Escape.percent_encoding escapes URI non-unreserved characters using percent-encoding.
  # It returns an instance of PercentEncoded.
  #
  # The unreserved characters are alphabet, digit, hyphen, dot, underscore and tilde.
  # [RFC 3986]
  #
  #  Escape.percent_encoding("foo") #=> #<Escape::PercentEncoded: foo>
  #
  #  Escape.percent_encoding(' !"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~')
  #  #=> #<Escape::PercentEncoded: %20%21%22%23%24%25%26%27%28%29%2A%2B%2C-.%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D~>
  def percent_encoding(str)
    s = str.gsub(%r{[^A-Za-z0-9\-._~]}n) {
      '%' + $&.unpack("H2")[0].upcase
    }
    PercentEncoded.new_no_dup(s)
  end

  # Escape.uri_segment escapes URI segment using percent-encoding.
  # It returns an instance of PercentEncoded.
  #
  #  Escape.uri_segment("a/b") #=> #<Escape::PercentEncoded: a%2Fb>
  #
  # The segment is "/"-splitted element after authority before query in URI, as follows.
  #
  #   scheme://authority/segment1/segment2/.../segmentN?query#fragment
  #
  # See RFC 3986 for details of URI.
  def uri_segment(str)
    # pchar - pct-encoded = unreserved / sub-delims / ":" / "@"
    # unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
    # sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
    s = str.gsub(%r{[^A-Za-z0-9\-._~!$&'()*+,;=:@]}n) {
      '%' + $&.unpack("H2")[0].upcase
    }
    PercentEncoded.new_no_dup(s)
  end

  # Escape.uri_path escapes URI path using percent-encoding.
  #
  # The given path should be one of follows.
  # * a sequence of (non-escaped) segments separated by "/".  (The segments cannot contains "/".)
  # * an array containing (non-escaped) segments.  (The segments may contains "/".)
  #
  # It returns an instance of PercentEncoded.
  #
  #  Escape.uri_path("a/b/c") #=> #<Escape::PercentEncoded: a/b/c>
  #  Escape.uri_path("a?b/c?d/e?f") #=> #<Escape::PercentEncoded: a%3Fb/c%3Fd/e%3Ff>
  #  Escape.uri_path(%w[/d f]) #=> "%2Fd/f"
  #
  # The path is the part after authority before query in URI, as follows.
  #
  #   scheme://authority/path#fragment
  #
  # See RFC 3986 for details of URI.
  #
  # Note that this function is not appropriate to convert OS path to URI.
  def uri_path(arg)
    if arg.respond_to? :to_ary
      s = arg.map {|elt| uri_segment(elt) }.join('/')
    else
      s = arg.gsub(%r{[^/]+}n) { uri_segment($&) }
    end
    PercentEncoded.new_no_dup(s)
  end

  # :stopdoc:
  def html_form_fast(pairs, sep='&')
    s = pairs.map {|k, v|
      # query-chars - pct-encoded - x-www-form-urlencoded-delimiters =
      #   unreserved / "!" / "$" / "'" / "(" / ")" / "*" / "," / ":" / "@" / "/" / "?"
      # query-char - pct-encoded = unreserved / sub-delims / ":" / "@" / "/" / "?"
      # query-char = pchar / "/" / "?" = unreserved / pct-encoded / sub-delims / ":" / "@" / "/" / "?"
      # unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
      # sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
      # x-www-form-urlencoded-delimiters = "&" / "+" / ";" / "="
      k = k.gsub(%r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n) {
        '%' + $&.unpack("H2")[0].upcase
      }
      v = v.gsub(%r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n) {
        '%' + $&.unpack("H2")[0].upcase
      }
      "#{k}=#{v}"
    }.join(sep)
    PercentEncoded.new_no_dup(s)
  end
  # :startdoc:

  # Escape.html_form composes HTML form key-value pairs as a x-www-form-urlencoded encoded string.
  # It returns an instance of PercentEncoded.
  #
  # Escape.html_form takes an array of pair of strings or
  # an hash from string to string.
  #
  #  Escape.html_form([["a","b"], ["c","d"]]) #=> #<Escape::PercentEncoded: a=b&c=d>
  #  Escape.html_form({"a"=>"b", "c"=>"d"}) #=> #<Escape::PercentEncoded: a=b&c=d>
  #
  # In the array form, it is possible to use same key more than once.
  # (It is required for a HTML form which contains
  # checkboxes and select element with multiple attribute.)
  #
  #  Escape.html_form([["k","1"], ["k","2"]]) #=> #<Escape::PercentEncoded: k=1&k=2>
  #
  # If the strings contains characters which must be escaped in x-www-form-urlencoded,
  # they are escaped using %-encoding.
  #
  #  Escape.html_form([["k=","&;="]]) #=> #<Escape::PercentEncoded: k%3D=%26%3B%3D>
  #
  # The separator can be specified by the optional second argument.
  #
  #  Escape.html_form([["a","b"], ["c","d"]], ";") #=> #<Escape::PercentEncoded: a=b;c=d>
  #
  # See HTML 4.01 for details.
  def html_form(pairs, sep='&')
    r = ''
    first = true
    pairs.each {|k, v|
      # query-chars - pct-encoded - x-www-form-urlencoded-delimiters =
      #   unreserved / "!" / "$" / "'" / "(" / ")" / "*" / "," / ":" / "@" / "/" / "?"
      # query-char - pct-encoded = unreserved / sub-delims / ":" / "@" / "/" / "?"
      # query-char = pchar / "/" / "?" = unreserved / pct-encoded / sub-delims / ":" / "@" / "/" / "?"
      # unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
      # sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
      # x-www-form-urlencoded-delimiters = "&" / "+" / ";" / "="
      r << sep if !first
      first = false
      k.each_byte {|byte|
        ch = byte.chr
        if %r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n =~ ch
          r << "%" << ch.unpack("H2")[0].upcase
        else
          r << ch
        end
      }
      r << '='
      v.each_byte {|byte|
        ch = byte.chr
        if %r{[^0-9A-Za-z\-\._~:/?@!\$'()*,]}n =~ ch
          r << "%" << ch.unpack("H2")[0].upcase
        else
          r << ch
        end
      }
    }
    PercentEncoded.new_no_dup(r)
  end

  class HTMLEscaped < StringWrapper
  end

  # :stopdoc:
  HTML_TEXT_ESCAPE_HASH = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
  }
  # :startdoc:

  # Escape.html_text escapes a string appropriate for HTML text using character references.
  # It returns an instance of HTMLEscaped.
  #
  # It escapes 3 characters:
  # * '&' to '&amp;'
  # * '<' to '&lt;'
  # * '>' to '&gt;'
  #
  #  Escape.html_text("abc") #=> #<Escape::HTMLEscaped: abc>
  #  Escape.html_text("a & b < c > d") #=> #<Escape::HTMLEscaped: a &amp; b &lt; c &gt; d>
  #
  # This function is not appropriate for escaping HTML element attribute
  # because quotes are not escaped.
  def html_text(str)
    s = str.gsub(/[&<>]/) {|ch| HTML_TEXT_ESCAPE_HASH[ch] }
    HTMLEscaped.new_no_dup(s)
  end

  # :stopdoc:
  HTML_ATTR_ESCAPE_HASH = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;',
  }
  # :startdoc:

  class HTMLAttrValue < StringWrapper
  end

  # Escape.html_attr_value encodes a string as a double-quoted HTML attribute using character references.
  # It returns an instance of HTMLAttrValue.
  #
  #  Escape.html_attr_value("abc") #=> #<Escape::HTMLAttrValue: "abc">
  #  Escape.html_attr_value("a&b") #=> #<Escape::HTMLAttrValue: "a&amp;b">
  #  Escape.html_attr_value("ab&<>\"c") #=> #<Escape::HTMLAttrValue: "ab&amp;&lt;&gt;&quot;c">
  #  Escape.html_attr_value("a'c") #=> #<Escape::HTMLAttrValue: "a'c">
  #
  # It escapes 4 characters:
  # * '&' to '&amp;'
  # * '<' to '&lt;'
  # * '>' to '&gt;'
  # * '"' to '&quot;'
  #
  def html_attr_value(str)
    s = '"' + str.gsub(/[&<>"]/) {|ch| HTML_ATTR_ESCAPE_HASH[ch] } + '"'
    HTMLAttrValue.new_no_dup(s)
  end

  # MIMEParameter represents parameter, token, quoted-string in MIME.
  # parameter and token is defined in RFC 2045.
  # quoted-string is defined in RFC 822.
  class MIMEParameter < StringWrapper
  end

  # predicate for MIME token.
  #
  # token is a sequence of any (US-ASCII) CHAR except SPACE, CTLs, or tspecials.
  def mime_token?(str)
    /\A[!\#-'*+\-.0-9A-Z^-~]+\z/ =~ str ? true : false
  end

  # :stopdoc:
  RFC2822_FWS = /(?:[ \t]*\r?\n)?[ \t]+/
  # :startdoc:

  # Escape.rfc2822_quoted_string escapes a string as quoted-string defined in RFC 2822.
  # It returns an instance of MIMEParameter.
  #
  # The obsolete syntax in quoted-string is not permitted.
  # For example, NUL causes ArgumentError.
  #
  # The given string may contain carriage returns ("\r") and line feeds ("\n").
  # However they must be part of folding white space: /\r\n[ \t]/ or /\n[ \t]/.
  # Escape.rfc2822_quoted_string assumes that newlines are represented as
  # "\n" or "\r\n".
  #
  # Escape.rfc2822_quoted_string does not permit consecutive sequence of
  # folding white spaces such as "\n \n ", according to RFC 2822 syntax.
  def rfc2822_quoted_string(str)
    if /\A(?:#{RFC2822_FWS}?[\x01-\x09\x0b\x0c\x0e-\x7f])*#{RFC2822_FWS}?\z/o !~ str
      raise ArgumentError, "not representable in quoted-string of RFC 2822: #{str.inspect}"
    end
    s = '"' + str.gsub(/["\\]/, '\\\\\&') + '"'
    MIMEParameter.new_no_dup(s)
  end

  # Escape.mime_parameter_value escapes a string as MIME parameter value in RFC 2045.
  # It returns an instance of MIMEParameter.
  #
  # MIME parameter value is token or quoted-string.
  # token is used if possible.
  def mime_parameter_value(str)
    if mime_token?(str)
      MIMEParameter.new(str)
    else
      rfc2822_quoted_string(str)
    end
  end

  # Escape.mime_parameter encodes attribute and value as MIME parameter in RFC 2045.
  # It returns an instance of MIMEParameter.
  #
  # ArgumentError is raised if attribute is not MIME token.
  #
  # ArgumentError is raised if value contains CR, LF or NUL.
  #
  #  Escape.mime_parameter("n", "v") #=> #<Escape::MIMEParameter: n=v>
  #  Escape.mime_parameter("charset", "us-ascii") #=> #<Escape::MIMEParameter: charset=us-ascii>
  #  Escape.mime_parameter("boundary", "gc0pJq0M:08jU534c0p") #=> #<Escape::MIMEParameter: boundary="gc0pJq0M:08jU534c0p">
  #  Escape.mime_parameter("boundary", "simple boundary") #=> #<Escape::MIMEParameter: boundary="simple boundary">
  def mime_parameter(attribute, value)
    unless mime_token?(attribute)
      raise ArgumentError, "not MIME token: #{attribute.inspect}"
    end
    MIMEParameter.new("#{attribute}=#{mime_parameter_value(value)}")
  end

  # predicate for MIME token.
  #
  # token is a sequence of any CHAR except CTLs or separators
  def http_token?(str)
    /\A[!\#-'*+\-.0-9A-Z^-z|~]+\z/ =~ str ? true : false 
  end

  # Escape.http_quoted_string escapes a string as quoted-string defined in RFC 2616.
  # It returns an instance of MIMEParameter.
  #
  # The given string may contain carriage returns ("\r") and line feeds ("\n").
  # However they must be part of folding white space: /\r\n[ \t]/ or /\n[ \t]/.
  # Escape.http_quoted_string assumes that newlines are represented as
  # "\n" or "\r\n".
  def http_quoted_string(str)
    if /\A(?:[\0-\x09\x0b\x0c\x0e-\xff]|\r?\n[ \t])*\z/ !~ str
      raise ArgumentError, "CR or LF not part of folding white space exists: #{str.inspect}"
    end
    s = '"' + str.gsub(/["\\]/, '\\\\\&') + '"'
    MIMEParameter.new_no_dup(s)
  end

  # Escape.http_parameter_value escapes a string as HTTP parameter value in RFC 2616.
  # It returns an instance of MIMEParameter.
  #
  # HTTP parameter value is token or quoted-string.
  # token is used if possible.
  def http_parameter_value(str)
    if http_token?(str)
      MIMEParameter.new(str)
    else
      http_quoted_string(str)
    end
  end

  # Escape.http_parameter encodes attribute and value as HTTP parameter in RFC 2616.
  # It returns an instance of MIMEParameter.
  #
  # ArgumentError is raised if attribute is not HTTP token.
  #
  # ArgumentError is raised if value is not representable in quoted-string.
  #
  #  Escape.http_parameter("n", "v") #=> #<Escape::MIMEParameter: n=v>
  #  Escape.http_parameter("charset", "us-ascii") #=> #<Escape::MIMEParameter: charset=us-ascii>
  #  Escape.http_parameter("q", "0.2") #=> #<Escape::MIMEParameter: q=0.2>
  def http_parameter(attribute, value)
    unless http_token?(attribute)
      raise ArgumentError, "not HTTP token: #{attribute.inspect}"
    end
    MIMEParameter.new("#{attribute}=#{http_parameter_value(value)}")
  end

  # :stopdoc:
  def _parse_http_params_args(args)
    pairs = []
    until args.empty?
      if args[0].respond_to?(:to_str) && args[1].respond_to?(:to_str)
        pairs << [args.shift, args.shift]
      else
        raise ArgumentError, "unexpected argument: #{args.inspect}"
      end
    end
    pairs
  end
  # :startdoc:

  # Escape.http_params_with_sep encodes parameters and joins with sep.
  #
  #  Escape.http_params_with_sep("; ", "foo", "bar")
  #  #=> #<Escape::MIMEParameter: foo=bar>
  #
  #  Escape.http_params_with_sep("; ", "foo", "bar", "hoge", "fuga")
  #  #=> #<Escape::MIMEParameter: foo=bar; hoge=fuga>
  #
  # If args are empty, empty MIMEParameter is returned.
  #
  #  Escape.http_params_with_sep("; ") #=> #<Escape::MIMEParameter: >
  #
  def http_params_with_sep(sep, *args)
    pairs = _parse_http_params_args(args)
    s = pairs.map {|attribute, value| http_parameter(attribute, value) }.join(sep)
    MIMEParameter.new_no_dup(s)
  end

  # Escape.http_params_with_pre encodes parameters and joins with given prefix.
  #
  #  Escape.http_params_with_pre("; ", "foo", "bar")                
  #  #=> #<Escape::MIMEParameter: ; foo=bar>
  #
  #  Escape.http_params_with_pre("; ", "foo", "bar", "hoge", "fuga")
  #  #=> #<Escape::MIMEParameter: ; foo=bar; hoge=fuga>
  #
  # If args are empty, empty MIMEParameter is returned.
  #
  #  Escape.http_params_with_pre("; ") #=> #<Escape::MIMEParameter: >
  #
  def http_params_with_pre(pre, *args)
    pairs = _parse_http_params_args(args)
    s = pairs.map {|attribute, value| pre + http_parameter(attribute, value).to_s }.join('')
    MIMEParameter.new_no_dup(s)
  end

end
