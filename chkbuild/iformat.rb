# chkbuild/iformat.rb - iformat object implementation.
#
# Copyright (C) 2006-2014 Tanaka Akira  <akr@fsij.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#  3. The name of the author may not be used to endorse or promote
#     products derived from this software without specific prior
#     written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

class ChkBuild::IFormat # internal format
  include Util

  def initialize(start_time, target, suffixes, depsuffixed_name, suffixed_name, opts)
    @t = start_time
    @target = target
    @suffixes = suffixes
    @suffixed_name = suffixed_name
    @depsuffixed_name = depsuffixed_name
    @target_dir = ChkBuild.build_top + @depsuffixed_name
    logdir_relpath = "#{@depsuffixed_name}/log"
    @public_logdir = ChkBuild.public_top+logdir_relpath
    current_txt_relpath = "#{@depsuffixed_name}/current.txt"
    @current_txt = ChkBuild.public_top+current_txt_relpath
    @opts = opts
    @page_uri_absolute = nil
    @page_uri_from_top = nil
  end
  attr_reader :target, :suffixes
  attr_reader :target_dir, :opts
  attr_reader :suffixed_name, :depsuffixed_name

  def inspect
    "\#<#{self.class}: #{self.depsuffixed_name}>"
  end

  def sort_times(times)
    u, l = times.partition {|d| /Z\z/ =~ d }
    u.sort!
    l.sort!
    l + u # chkbuild used localtime at old time.
  end

  ################

  def internal_format
    if child_format_wrapper(nil)
      exit 0
    else
      exit 1
    end
  end

  def child_format_wrapper(parent_pipe)
    @errors = []
    child_format_target
  end

  def make_local_tmpdir
    tmpdir = @build_dir + 'tmp'
    tmpdir.mkdir(0700) unless File.directory? tmpdir
    ENV['TMPDIR'] = tmpdir.to_s
  end

  def child_format_target
    if @opts[:nice]
      begin
        Process.setpriority(Process::PRIO_PROCESS, 0, @opts[:nice])
      rescue Errno::EACCES # already niced.
      end
    end
    setup_format
    title, title_version, title_assoc = gen_title
    update_result(title, title_version, title_assoc)
    show_title_info(title, title_version, title_assoc)
    @logfile.start_section 'end2'
  end

  def setup_format
    @build_dir = ChkBuild.build_top + @t
    @log_filename = @build_dir + 'log'
    mkcd @target_dir
    Dir.chdir @t
    @logfile = ChkBuild::LogFile.append_open(@log_filename)
    @logfile.change_default_output
    #(ChkBuild.public_top+@depsuffixed_name).mkpath
    #@public_logdir.mkpath
    #force_link "log", @current_txt
    make_local_tmpdir
  end

  def show_title_info(title, title_version, title_assoc)
    @logfile.start_section 'title-info'
    puts "title-info title:#{Escape._ltsv_val(title)}"
    puts "title-info title_version:#{Escape._ltsv_val(title_version)}"
    title_assoc.each {|k, v|
      puts "title-info #{Escape._ltsv_key k}:#{Escape._ltsv_val v}"
    }
  end

  class LineReader
    def initialize(filename)
      @filename = filename
    end

    def each_line
      empty_lines = []
      if /\.gz\z/ =~ @filename.to_s
        Zlib::GzipReader.wrap(open(@filename)) {|f|
          f.each_line {|line|
            line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
	    if /\A\s*\z/ =~ line
	      empty_lines << line
	    else
	      empty_lines.each {|el| yield el }
	      empty_lines = []
	      yield line
	    end
          }
        }
      else
        open(@filename) {|f|
          f.each_line {|line|
            line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
	    if /\A\s*\z/ =~ line
	      empty_lines << line
	    else
	      empty_lines.each {|el| yield el }
	      empty_lines = []
	      yield line
	    end
          }
        }
      end
    end
  end

  def with_page_uri_from_top(relpath, absolute_arg=nil)
    if @page_uri_from_top != nil
      raise "with_page_uri_from_top is called recursively"
    end
    begin
      @page_uri_from_top = relpath
      @page_uri_absolute = absolute_arg
      yield
    ensure
      @page_uri_from_top = nil
      @page_uri_absolute = nil
    end
  end

  def uri_from_top(relpath, absolute_arg=nil)
    abs = if absolute_arg != nil
	    absolute_arg
	  elsif @page_uri_absolute != nil
	    @page_uri_absolute
	  else
	    false
	  end
    if abs
      reluri = relpath.gsub(%r{[^/]+}) { u($&) }
      "#{ChkBuild.top_uri}#{reluri}"
    else
      n = @page_uri_from_top.count("/")
      r = relpath
      while 0 < n && %r{/} =~ r
        n -= 1
	r = $'
      end
      reluri = r.gsub(%r{[^/]+}) { u($&) }
      if 0 < n
	reluri = "../" * n + (reluri == '.' ? '' : reluri)
      end
      reluri
    end
  end

  def update_result(title, title_version, title_assoc)
    @last_txt_relpath = "#{@depsuffixed_name}/last.txt"
    @last_html_relpath = "#{@depsuffixed_name}/last.html"
    @last_html_gz_relpath = "#{@depsuffixed_name}/last.html.gz"
    @summary_html_relpath = "#{@depsuffixed_name}/summary.html"
    @summary_txt_relpath = "#{@depsuffixed_name}/summary.txt"
    @summary_ltsv_relpath = "#{@depsuffixed_name}/summary.ltsv"
    @recent_html_relpath = "#{@depsuffixed_name}/recent.html"
    @recent_ltsv_relpath = "#{@depsuffixed_name}/recent.ltsv"
    @rss_relpath = "#{@depsuffixed_name}/rss"
    @compressed_rawfail_relpath = "#{@depsuffixed_name}/log/#{@t}.fail.txt.gz"
    @compressed_rawdiff_relpath = "#{@depsuffixed_name}/log/#{@t}.diff.txt.gz"
    @compressed_loghtml_relpath = "#{@depsuffixed_name}/log/#{@t}.log.html.gz"
    @compressed_failhtml_relpath = "#{@depsuffixed_name}/log/#{@t}.fail.html.gz"
    @compressed_diffhtml_relpath = "#{@depsuffixed_name}/log/#{@t}.diff.html.gz"

    store_title_version(title_version)
    force_link @current_txt, ChkBuild.public_top+@last_txt_relpath if @current_txt.file?
    make_logfail_text_gz(@log_filename, ChkBuild.public_top+@compressed_rawfail_relpath)
    failure = detect_failure(@t)
    @current_status = (failure || :success).to_s
    @has_neterror = failure == :netfail
    @older_time, older_time_failure = find_diff_target_time(@t)
    @older_status = @older_time ? (older_time_failure || :success).to_s : nil
    @compressed_older_loghtml_relpath = @older_time ? "#{@depsuffixed_name}/log/#{@older_time}.log.html.gz" : nil
    @compressed_older_failhtml_relpath = @older_time ? "#{@depsuffixed_name}/log/#{@older_time}.fail.html.gz" : nil
    @compressed_older_diffhtml_relpath = @older_time ? "#{@depsuffixed_name}/log/#{@older_time}.diff.html.gz" : nil
    different_sections = make_diff(@older_time, @t)
    @diff_reader = LineReader.new(ChkBuild.public_top+@compressed_rawdiff_relpath)
    @log_reader = LineReader.new(@log_filename)
    @fail_reader = LineReader.new(ChkBuild.public_top+@compressed_rawfail_relpath)
    update_summary(title, different_sections, title_assoc)
    update_recent
    make_last_html(title, different_sections)
    Util.compress_file(ChkBuild.public_top+@last_html_relpath, ChkBuild.public_top+@last_html_gz_relpath)
    make_loghtml(title, different_sections)
    make_failhtml(title)
    make_diffhtml(title, different_sections)
    make_rss(title, different_sections)
    update_older_page if @older_time && failure != :netfail
  end

  def update_older_page
    block = lambda {|src, dst|
      src.each_line {|line|
        line = line.gsub(/<!--placeholder_start-->(?:nextdiff|newerdiff|NewerDiff)<!--placeholder_end-->/) {
	  "<a href=#{ha uri_from_top(@compressed_diffhtml_relpath) }>NewerDiff</a>"
	}
        line = line.gsub(/<!--placeholder_start-->(?:nextlog|newerlog|NewerLog)<!--placeholder_end-->/) {
	  "<a href=#{ha uri_from_top(@compressed_loghtml_relpath) }>#{@t}</a>" +
	  "(<a href=#{ha uri_from_top(@compressed_failhtml_relpath) }>#{h @current_status}</a>)"
	}
	dst.print line
      }
    }
    with_page_uri_from_top(@compressed_older_loghtml_relpath) {
      update_gziped_file(ChkBuild.public_top+@compressed_older_loghtml_relpath, &block)
    }
    with_page_uri_from_top(@compressed_older_failhtml_relpath) {
      update_gziped_file(ChkBuild.public_top+@compressed_older_failhtml_relpath, &block)
    }
    with_page_uri_from_top(@compressed_older_diffhtml_relpath) {
      update_gziped_file(ChkBuild.public_top+@compressed_older_diffhtml_relpath, &block)
    }
  end

  def update_gziped_file(filename)
    return if !File.file?(filename)
    atomic_make_compressed_file(filename) {|dst|
      Zlib::GzipReader.wrap(open(filename)) {|src|
	yield src, dst
      }
    }
  end

  def gen_title
    titlegen = ChkBuild::Title.new(@target, @logfile)
    title_succ = iformat_catch_error('run_hooks') { titlegen.run_hooks }
    title = titlegen.make_title
    title << " (titlegen.run_hooks error)" if !title_succ
    title_version = titlegen.version.strip
    title_assoc = []
    titlegen.keys.each {|k|
      title_assoc << [k.to_s, titlegen[k].to_s]
    }
    titlegen.hidden_keys.each {|k|
      title_assoc << [k.to_s, titlegen[k].to_s]
    }
    return title, title_version, title_assoc
  end

  def store_title_version(title_version)
    (ChkBuild.build_top+@depsuffixed_name+@t+"VERSION").open("w") {|f|
      f.puts title_version
    }
  end

  attr_reader :logfile

  def iformat_catch_error(name=nil)
    unless defined?(@errors) && defined?(@logfile) && defined?(@build_dir)
      # logdiff?
      return yield
    end
    err = nil
    begin
      yield
    rescue Exception => err
    end
    return true unless err
    @errors << err
    @logfile.start_section("#{name} error") if name
    show_backtrace err
    GDB.check_core(@build_dir)
    if err.respond_to? :reason
      puts "failed(#{err.reason} #{err.class})"
    else
      puts "failed(#{err.class})"
    end
    return false
  end

  def build_dir() @build_dir end

  def update_summary(title, different_sections, title_assoc)
    if different_sections
      if different_sections.empty?
        diff_txt = "diff"
      else
	different_sections = different_sections.map {|secname|
          secname.sub(%r{(.)/.*\z}) { "#$1/" }
        }.uniq
        diff_txt = "diff:#{different_sections.join(',')}"
      end
    end
    open(ChkBuild.public_top+@summary_txt_relpath, "a") {|f|
      f.print "#{@t}(#{@current_status}) #{title}"
      f.print " (#{diff_txt})" if diff_txt
      f.puts
    }
    with_page_uri_from_top(@summary_html_relpath) {
      open(ChkBuild.public_top+@summary_html_relpath, "a") {|f|
	if f.stat.size == 0
	  page_title = "#{@depsuffixed_name} build summary (#{ChkBuild.nickname})"
	  f.puts "<title>#{h page_title}</title>"
	  f.puts "<h1>#{h page_title}</h1>"
	  f.puts "<p><a href=#{ha uri_from_top('.')}>chkbuild</a></p>"
	end
	f.print "<a href=#{ha uri_from_top(@compressed_loghtml_relpath)} name=#{ha @t}>#{h @t}</a>"
	f.print "(<a href=#{ha uri_from_top(@compressed_failhtml_relpath)} name=#{ha @t}>#{h @current_status}</a>)"
	f.print " #{h title}"
	if diff_txt
	  f.print " (<a href=#{ha uri_from_top(@compressed_diffhtml_relpath)}>#{h diff_txt}</a>)"
	else
	  f.print " (<a href=#{ha uri_from_top(@compressed_diffhtml_relpath)}>no diff</a>)"
	end
	f.puts "<br>"
      }
      open(ChkBuild.public_top+@summary_ltsv_relpath, "a") {|f|
        assoc = []
        assoc << ["host", ChkBuild.nickname]
        assoc << ["depsuffixed_name", @depsuffixed_name]
        assoc << ["start_time", @t]
        assoc << ["result", @current_status]
        assoc << ["title", title]
        assoc << ["compressed_loghtml_relpath", uri_from_top(@compressed_loghtml_relpath)]
        assoc << ["compressed_failhtml_relpath", uri_from_top(@compressed_failhtml_relpath)]
        assoc << ["compressed_diffhtml_relpath", uri_from_top(@compressed_diffhtml_relpath)]
        assoc << ["different_sections", different_sections.join(',')] if different_sections
        title_assoc.each {|k, v|
          assoc << [k.to_s, v.to_s]
        }
        f.print Escape.ltsv_line(assoc)
      }
    }
  end

  RECENT_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
    <link rel="alternate" type="application/rss+xml" title="RSS" href=<%=ha uri_from_top(@rss_relpath, true) %>>
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
<%= recent_summary.chomp %>
    <hr>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
  </body>
</html>
End

  def update_recent
    update_recent_html
    update_recent_ltsv
  end

  def update_recent_html
    summary_path = ChkBuild.public_top+@summary_html_relpath
    lines = []
    summary_path.open {|f|
      while l = f.gets
        lines << l
        lines.shift if 100 < lines.length
      end
    }
    while !lines.empty? && /\A<a / !~ lines[0]
      lines.shift
    end

    # variables for RECENT_HTMLTemplate:
    title = "#{@depsuffixed_name} recent build summary (#{ChkBuild.nickname})"
    recent_summary = lines.reverse.join

    content = with_page_uri_from_top(@recent_html_relpath) {
      ERB.new(RECENT_HTMLTemplate).result(binding)
    }

    recent_path = ChkBuild.public_top+@recent_html_relpath
    atomic_make_file(recent_path) {|f| f << content }
  end

  def update_recent_ltsv
    summary_path = ChkBuild.public_top+@summary_ltsv_relpath
    lines = []
    summary_path.open {|f|
      while l = f.gets
        lines << l
        lines.shift if 100 < lines.length
      end
    }

    content = lines.reverse.join('')
    recent_path = ChkBuild.public_top+@recent_ltsv_relpath
    atomic_make_file(recent_path) {|f| f << content }
  end

  def list_tags(log)
    tags = []
    lastline = ''
    log.each_line {|line|
      if /\A== (\S+)/ =~ line
        if !tags.empty?
	  tags.last << !ChkBuild::LogFile.failed_line?(lastline)
	end
        tags << [$1]
      end
      if /\A\s*\z/ !~ line
        lastline = line
      end
    }
    if !tags.empty?
      tags.last << !ChkBuild::LogFile.failed_line?(lastline)
    end
    tags
  end

  def encode_invalid(str)
    if str.respond_to? :ascii_only?
      if str.ascii_only?
        ustr = str.dup.force_encoding("UTF-8")
	ustr
      else
        locale_encoding = Encoding.find("locale")
        if locale_encoding == Encoding::US_ASCII
          ustr = str.dup.force_encoding("ASCII-8BIT")
          ustr.gsub!(/[^\x00-\x7f]/, '?')
          ustr.force_encoding("UTF-8")
        else
          hstr = str.encode("US-ASCII", Encoding.find("locale"),
                            :invalid=>:replace, :undef=>:replace, :xml=>:text)
          ustr = hstr.gsub(/&(amp|lt|gt|\#x([0-9A-F]+));/) {
            case $1
            when 'amp' then '&'
            when 'lt' then '<'
            when 'gt' then '>'
            else
              [$2.to_i(16)].pack("U")
            end
          }
        end
	ustr
      end
    else
      str = str.gsub(/[^\t\r\n -~]+/) {|invalid|
	"[" + invalid.unpack("H*")[0] + "]"
      }
    end
  end

  def markup_uri(line, result)
    i = 0
    line.scan(/#{URI.regexp(['http', 'https'])}/o) {
      match = $~
      if /\A[a-z]+:\z/ =~ match[0]
        result << h(line[i...match.end(0)]) if i < match.end(0)
      else
        result << h(line[i...match.begin(0)]) if i < match.begin(0)
        result << "<a href=#{ha match[0]}>#{h match[0]}</a>"
      end
      i = match.end(0)
    }
    result << h(line[i...line.length]) if i < line.length
    result
  end

  def markup_log_line(line)
    line = encode_invalid(line)
    result = ''
    if /\A== (\S+)/ =~ line
      tag = $1
      rest = $'
      result << "<a name=#{ha(u(tag))} href=#{ha uri_from_top(@compressed_loghtml_relpath)+"##{u(tag)}"}>== #{h(tag)}#{h(rest)}</a>"
    else
      markup_uri(line, result)
    end
    result
  end

  def markup_fail_line(line)
    line = encode_invalid(line)
    result = ''
    if /\A== (\S+)/ =~ line
      tag = $1
      rest = $'
      result << "<a name=#{ha(u(tag))} href=#{ha uri_from_top(@compressed_failhtml_relpath)+"##{u(tag)}"}>== #{h(tag)}#{h(rest)}</a>"
      result << " (<a href=#{ha uri_from_top(@compressed_loghtml_relpath)+"##{u(tag)}"}>full</a>)"
    else
      markup_uri(line, result)
    end
    result
  end

  def markup_diff_line(line)
    line = encode_invalid(line)
    if %r{\A((?:OLDREV|NEWREV|CHG|ADD|DEL|COMMIT) .*)\s(https?://\S*)\s*\z} =~ line
      content = $1
      url = $2
      "<a href=#{ha url}>#{h content.strip}</a>"
    else
      result = ''
      markup_uri(line, result)
      result
    end
  end

  def markup_diff(str)
    result = ''
    str.each_line {|line|
      result << markup_diff_line(line)
    }
    result
  end

  def no_differences_message
    if @current_status == 'success'
      "<p>Success</p>"
    elsif @older_time
      "<p>Failed as the <a href=#{ha uri_from_top(@compressed_older_loghtml_relpath)}>previous build</a>.\n" +
      "See the <a href=#{ha uri_from_top(@compressed_loghtml_relpath)}>current full build log</a>.</p>"
    else
      "<p>Failed.\n" +
      "See the <a href=#{ha uri_from_top(@compressed_loghtml_relpath)}>full build log</a>.</p>"
    end
  end

  LAST_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
    <link rel="alternate" type="application/rss+xml" title="RSS" href=<%=ha uri_from_top(@rss_relpath, true) %>>
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>ThisDiff</a> &gt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>)
    </p>
% if has_diff
    <pre>
%     @diff_reader.each_line {|line|
<%=     markup_diff_line line.chomp %>
%     }
</pre>
% else
    <%= no_differences_message %>
% end
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>ThisDiff</a> &gt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>)
    </p>
    <hr>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
  </body>
</html>
End

  def make_last_html(title, has_diff)
    atomic_make_file(ChkBuild.public_top+@last_html_relpath) {|_erbout|
      with_page_uri_from_top(@last_html_relpath) {
	ERBIO.new(LAST_HTMLTemplate, nil, '%').result(binding)
      }
    }
  end

  DIFF_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>ThisDiff</a> &gt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>) &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end-->
    </p>
% if has_diff
    <pre>
%     @diff_reader.each_line {|line|
<%=     markup_diff_line line.chomp %>
%     }
</pre>
% else
    <%= no_differences_message %>
% end
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>ThisDiff</a> &gt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>) &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end-->
    </p>
    <hr>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
  </body>
</html>
End

  def make_diffhtml(title, has_diff)
    atomic_make_compressed_file(ChkBuild.public_top+@compressed_diffhtml_relpath) {|_erbout|
      with_page_uri_from_top(@compressed_diffhtml_relpath) {
	ERBIO.new(DIFF_HTMLTemplate, nil, '%').result(binding)
      }
    }
  end

  LOG_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>) &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end--> &gt;
      <!--placeholder_start-->NewerLog<!--placeholder_end-->
    </p>
    <ul>
% list_tags(@log_reader).each {|tag, success|
      <li><a href=<%=ha("#"+u(tag)) %>><%=h tag %></a><%= success ? "" : " failed" %></li>
% }
    </ul>
    <pre>
% @log_reader.each_line {|line|
<%= markup_log_line line.chomp %>
% }
</pre>
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a> &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a> &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end--> &gt;
      <!--placeholder_start-->NewerLog<!--placeholder_end-->
    </p>
    <hr>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
  </body>
</html>
End

  def make_loghtml(title, has_diff)
    atomic_make_compressed_file(ChkBuild.public_top+@compressed_loghtml_relpath) {|_erbout|
      with_page_uri_from_top(@compressed_loghtml_relpath) {
	ERBIO.new(LOG_HTMLTemplate, nil, '%').result(binding)
      }
    }
  end

  RSS_CONTENT_HTMLTemplate = <<'End'
<p>
% if @older_time
  <a href=<%=ha uri_from_top(@compressed_older_diffhtml_relpath) %>>OlderDiff</a> &lt;
  <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
  %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
  <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>ThisDiff</a> &gt;
  <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a><%
  %>(<a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>)
</p>
% if has_diff
<pre>
%   n = 0
%   @diff_reader.each_line {|line|
%     n += 1
%     break if max_diff_lines < n
<%=   markup_diff_line line.chomp %>
%   }
%   if max_diff_lines < n
...(omitted)...
%   end
</pre>
%   if max_diff_lines < n
<p><a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>read more differences</a></p>
%   end
% else
<%= no_differences_message %>
% end
<p>
% if @older_time
  <a href=<%=ha uri_from_top(@compressed_older_diffhtml_relpath) %>>OlderDiff</a> &lt;
  <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a> &lt;
% end
  <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>ThisDiff</a> &gt;
  <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a>
</p>
End

  def make_rss_html_content(has_diff)
    # variables for RSS_CONTENT_HTMLTemplate:
    max_diff_lines = 500

    ERB.new(RSS_CONTENT_HTMLTemplate, nil, '%').result(binding)
  end

  def make_rss(title, has_diff)
    with_page_uri_from_top(@rss_relpath, true) {
      latest_url = uri_from_top(@compressed_diffhtml_relpath)
      if (ChkBuild.public_top+@rss_relpath).exist?
	rss = RSS::Parser.parse((ChkBuild.public_top+@rss_relpath).read)
	olditems = rss.items
	n = 24
	if n < olditems.length
	  olditems = olditems.sort_by {|item| item.date }[-n,n]
	end
      else
	olditems = []
      end
      rss = RSS::Maker.make("1.0") {|maker|
	maker.channel.about = uri_from_top(@rss_relpath)
	maker.channel.title = "#{@depsuffixed_name} (#{ChkBuild.nickname})"
	maker.channel.description = "chkbuild #{@depsuffixed_name}"
	maker.channel.link = uri_from_top(@depsuffixed_name)
	maker.items.do_sort = true
	olditems.each {|olditem|
	  maker.items.new_item {|item|
	    item.link = olditem.link
	    item.title = olditem.title
	    item.date = olditem.date
	    item.content_encoded = olditem.content_encoded
	  }
	}
	maker.items.new_item {|item|
	  item.link = latest_url
	  item.title = title
	  item.date = Time.parse(@t)
	  item.content_encoded = make_rss_html_content(has_diff)
	}
      }
      atomic_make_file(ChkBuild.public_top+@rss_relpath) {|f| f.puts rss.to_s }
    }
  end

  def show_backtrace(err=$!)
    puts "|#{err.message} (#{err.class})"
    err.backtrace.each {|pos| puts "| #{pos}" }
  end

  def detect_failure(time)
    open_gziped_log(time) {|f|
      net = false
      failure = false
      ChkBuild::LogFile.each_log_line(f) {|tag, line|
        if tag == :header
          _, secname, _ = ChkBuild::LogFile.parse_section_header(line)
          if secname == 'neterror'
            net = true
          end
        elsif tag == :fail
          failure = true
        end
      }
      if net
        return :netfail
      end
      if failure
        return :failure
      end
      nil
    }
  end

  def find_diff_target_time(time2)
    entries = Dir.entries(@public_logdir)
    h = {}
    time_seq = []
    entries.each {|f|
      h[f] = true
      if /\A(\d{8}T\d{6}Z?)(?:\.log)?\.txt\.gz\z/ =~ f # year 10000 problem
        time_seq << $1
      end
    }
    time2_failure = detect_failure(time2)
    time_seq = sort_times(time_seq)
    time_seq.delete time2
    time1_failure = nil
    time_seq.reverse_each {|time1|
      if !h["#{time1}.log.txt.gz"] ||
         !h["#{time1}.diff.txt.gz"] ||
         !h["#{time1}.log.html.gz"] ||
         !h["#{time1}.diff.html.gz"]
        next
      end
      if time2_failure != :netfail
        time1_failure = detect_failure(time1)
        if time1_failure == :netfail
          next
        end
      end
      return [time1, time1_failure]
    }
    nil
  end

  def make_diff(time1, time2)
    output_path = ChkBuild.public_top+@compressed_rawdiff_relpath
    if !time1
      Zlib::GzipWriter.wrap(open(output_path, "w")) {}
      return nil
    end
    different_sections = nil
    Zlib::GzipWriter.wrap(open(output_path, "w")) {|z|
      different_sections = output_diff(time1, time2, z)
    }
    if !different_sections
      return nil
    end
    return different_sections
  end

  def output_diff(t1, t2, out)
    has_change_line = output_change_lines2(t1, t2, out)
    has_change_line |= output_change_lines(t2, out)
    tmp1 = make_diff_content(t1)
    tmp2 = make_diff_content(t2)
    header1 = "--- #{t1}\n"
    header2 = "+++ #{t2}\n"
    diffsecs = { :old => {}, :new => {} }
    current_section = {}
    scanner = lambda {|mode, linenum, mark, line|
      current_section[mode] = $1 if /\A== (\S+)/ =~ line
      if mark != ' '
        diffsecs[mode][current_section[mode]] ||= linenum
      end
      #open("/dev/tty", "w") {|f| f.puts [mode, linenum, mark, line].inspect }
    }
    has_diff = has_change_line | Lchg.diff(tmp1.path, tmp2.path, out, header1, header2, scanner)
    return nil if !has_diff
    ret = []
    ret << 'src' if has_change_line
    different_sections = diffsecs[:new].keys.sort_by {|k| diffsecs[:new][k] }
    different_sections |= diffsecs[:old].keys.sort_by {|k| diffsecs[:old][k] }
    ret.concat different_sections
    ret
  end

  def output_change_lines(t2, out)
    has_diff = false
    open_gziped_log(t2) {|f|
      has_change_line = false
      f.each {|line|
	line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
        if ChkBuild::CHANGE_LINE_PAT =~ line
          out.puts line
          has_change_line = true
        end
      }
      if has_change_line
        out.puts
        has_diff = true
      end
    }
    has_diff
  end

  def collect_checkout_log(t)
    result = []
    open_gziped_log(t) {|f|
      lines = nil
      f.each {|line|
	line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
        # CHECKOUT svn http://svn.ruby-lang.org/repos/ruby trunk
	# VIEWER ViewVC http://svn.ruby-lang.org/cgi-bin/viewvc.cgi?diff_format=u
	# DIRECTORY .     28972
	# FILE .document  27092   sha256:88112f5a76d27b7a4b0623a1cbda18d2dd0bc4b3847fc47812fb3a3052f2bcee
	# LASTCOMMIT 66c9eb68ccdc473025d2f6fb34019fc3a977c252
	if !lines
	  if /\ACHECKOUT / =~ line
	    result << lines if lines
	    lines = [line]
	  end
	else
	  case line
	  when /\AVIEWER /, /\ADIRECTORY /, /\AFILE /, /\ALASTCOMMIT /
	    lines << line
	  else
	    result << lines
	    lines = nil
	  end
	end
      }
      result << lines if lines
    }
    result
  end

  def generic_output_change_lines(checkout_line, lines1, lines2, out)
    out.puts "CHG #{checkout_line}"
    lines1 = lines1.sort
    lines2 = lines2.sort
    while !lines1.empty? && !lines2.empty?
      c = lines1.first <=> lines2.first
      if c == 0
        lines1.shift
        lines2.shift
	next
      end
      if c < 0
        out.puts "- #{lines1.first}"
	lines1.shift
	next
      end
      if c > 0
        out.puts "+ #{lines2.first}"
	lines2.shift
	next
      end
    end
    while !lines1.empty?
      out.puts "- #{lines1.first}"
      lines1.shift
    end
    while !lines2.empty?
      out.puts "+ #{lines2.first}"
      lines2.shift
      next
    end
  end

  def output_change_lines2(t1, t2, out)
    has_change_line = false
    a1 = collect_checkout_log(t1)
    h1 = {}
    a1.each {|lines| h1[lines[0]] = lines[1..-1] }
    a2 = collect_checkout_log(t2)
    h2 = {}
    a2.each {|lines| h2[lines[0]] = lines[1..-1] }
    checkout_lines = a1.map {|lines| lines[0] }
    checkout_lines |= a2.map {|lines| lines[0] }
    checkout_lines.each {|checkout_line|
      lines1 = h1[checkout_line]
      lines2 = h2[checkout_line]
      next if lines1 == lines2
      has_change_line = true
      if lines1 && lines2
        if /\ACHECKOUT\s+([a-z]+)/ =~ checkout_line
	  reptype = $1
	  meth = "output_#{reptype}_change_lines"
	  if self.respond_to? meth
	    self.send(meth, checkout_line, lines1, lines2, out)
	  else
	    generic_output_change_lines(checkout_line, lines1, lines2, out)
	  end
	end
      else
        if lines1
	  out.puts "DEL #{checkout_line}"
	else
	  out.puts "ADD #{checkout_line}"
	end
      end
    }
    out.puts if has_change_line
    has_change_line
  end

  def make_diff_content(time)
    build_dir = ChkBuild.build_top
    timemap = { time => "<buildtime>", "#{build_dir}/#{time}" => "<build-dir>" }
    uncompressed = Tempfile.open("#{time}.u.")
    open_gziped_log(time) {|z|
      FileUtils.copy_stream(z, uncompressed)
    }
    uncompressed.flush
    logfile = ChkBuild::LogFile.read_open(uncompressed.path)
    logfile.dependencies.each {|dep_suffixed_name, dep_time, dep_version|
      target_name = dep_suffixed_name.sub(/[-_].*\z/, '')
      timemap[dep_time] = "<#{target_name}-buildtime>"
      timemap["#{build_dir}/#{dep_time}"] = "<#{target_name}-build-dir>"
    }
    pat = Regexp.union(*timemap.keys)
    tmp = Tempfile.open("#{time}.d.")
    state = {}
    open_gziped_log(time) {|z|
      z.each_line {|line|
	line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
        line = line.gsub(pat) { timemap[$&] }
	ChkBuild.fetch_diff_preprocess_hook(@target.target_name).each {|block|
          iformat_catch_error(block.to_s) { line = block.call(line, state) }
        }
        tmp << line
      }
    }
    tmp.flush
    tmp
  end

  def sort_diff_content(time1, tmp1, time2, tmp2)
    pat = ChkBuild.diff_preprocess_sort_pattern(@target.target_name)
    return tmp1, tmp2 if !pat

    h1, h2 = [tmp1, tmp2].map {|tmp|
      h = {}
      tmp.rewind
      tmp.gather_each(pat) {|lines|
        next unless 1 < lines.length && pat =~ lines.first
        h[$&] = Digest::SHA256.hexdigest(lines.sort.join(''))
      }
      h
    }

    h0 = {}
    h1.each_key {|k| h0[k] = true if h1[k] == h2[k]  }

    newtmp1, newtmp2 = [[time1, tmp1], [time2, tmp2]].map {|time, tmp|
      newtmp = Tempfile.open("#{time}.d.")
      tmp.rewind
      tmp.gather_each(pat) {|lines|
        if 1 < lines.length && pat =~ lines.first && h0[$&]
          newtmp.print lines.sort.join('')
        else
          newtmp.print lines.join('')
        end
      }
      tmp.close(true)
      newtmp.rewind
      newtmp
    }

    return newtmp1, newtmp2
  end

  FAIL_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a>(<%
      %><a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>) &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end--> &gt;
      <!--placeholder_start-->NewerLog<!--placeholder_end-->
    </p>
% tags = list_tags(@fail_reader)
% if !tags.empty?
    <ul>
%    tags.each {|tag, success|
      <li><a href=<%=ha("#"+u(tag)) %>><%=h tag %></a><%= success ? "" : " failed" %></li>
%    }
    </ul>
% end
    <pre>
% fail_log_numlines = 0
% @fail_reader.each_line {|line|
%   fail_log_numlines += 1
<%= markup_fail_line line.chomp %>
% }
% if fail_log_numlines == 0
No failures.
% end
</pre>
    <p>
% if @older_time
      <a href=<%=ha uri_from_top(@compressed_older_loghtml_relpath) %>><%=h @older_time %></a><%
      %>(<a href=<%=ha uri_from_top(@compressed_older_failhtml_relpath) %>><%=h @older_status %></a>) &lt;
% end
      <a href=<%=ha uri_from_top(@compressed_diffhtml_relpath) %>>OlderDiff</a> &lt;
      <a href=<%=ha uri_from_top(@compressed_loghtml_relpath) %>><%=h @t %></a>(<%
      %><a href=<%=ha uri_from_top(@compressed_failhtml_relpath) %>><%=h @current_status %></a>) &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end--> &gt;
      <!--placeholder_start-->NewerLog<!--placeholder_end-->
    </p>
    <hr>
    <p>
      <a href=<%=ha uri_from_top(".") %>>chkbuild</a>
      <a href=<%=ha uri_from_top(@summary_html_relpath) %>>summary</a>
      <a href=<%=ha uri_from_top(@recent_html_relpath) %>>recent</a>
      <a href=<%=ha uri_from_top(@last_html_gz_relpath) %>>last</a>
    </p>
  </body>
</html>
End

  def make_failhtml(title)
    atomic_make_compressed_file(ChkBuild.public_top+@compressed_failhtml_relpath) {|_erbout|
      with_page_uri_from_top(@compressed_failhtml_relpath) {
	ERBIO.new(FAIL_HTMLTemplate, nil, '%').result(binding)
      }
    }
  end

  def make_logfail_text_gz(log_txt_filename, dst_gz_filename)
    atomic_make_compressed_file(dst_gz_filename) {|z|
      open(log_txt_filename) {|input|
        extract_failures(input, z)
      }
    }
  end

  def output_fail(time, output)
    open_gziped_log(time) {|log|
      extract_failures(log, output)
    }
  end

  def extract_failures(input, output)
    section_header = ''
    section_lines = []
    section_failed = nil
    section_numlines = 0
    failure_start_pattern = nil
    ChkBuild::LogFile.each_log_line(input) {|tag, line|
      if tag == :header
        _, secname, _ = ChkBuild::LogFile.parse_section_header(line)
        if secname == 'neterror'
          section_failed = true
        end
        if !section_lines.empty? && section_failed
          failure_found(section_header, section_numlines, section_lines, output)
        end
        section_header = line
        section_lines = []
        section_failed = false
        section_numlines = 0
        failure_start_pattern = ChkBuild.fetch_failure_start_pattern(@target.target_name, secname)
      else
        if tag == :fail
          section_failed = true
        end
        section_lines << line
        if failure_start_pattern
          if failure_start_pattern =~ line
            failure_start_pattern = nil
          elsif 10 < section_lines.length
            section_lines.shift
          end
        end
        section_numlines += 1
      end
    }
    if !section_lines.empty? && section_failed
      failure_found(section_header, section_numlines, section_lines, output)
    end
  end

  def failure_found(section_header, section_numlines, section_lines, output)
    output << section_header
    if section_numlines != section_lines.length
      output << "...(snip #{section_numlines - section_lines.length} lines)...\n"
    end
    section_lines.each {|l| output << l }
  end

  def open_gziped_log(time, &block)
    if File.file?(@public_logdir+"#{time}.log.txt.gz")
      filename = @public_logdir+"#{time}.log.txt.gz"
    else
      filename = @public_logdir+"#{time}.txt.gz"
    end
    Zlib::GzipReader.wrap(open(filename), &block)
  end

end
