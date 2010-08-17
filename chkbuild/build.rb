# chkbuild/build.rb - build object implementation.
#
# Copyright (C) 2006,2007,2008,2009,2010 Tanaka Akira  <akr@fsij.org>
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

require 'fileutils'
require 'time'
require 'zlib'
require "uri"
require "tempfile"
require "pathname"
require "rbconfig"
require "rss"

require 'escape'
require 'timeoutcom'
require 'gdb'
require "lchg"
require "util"
require "erbio"

module ChkBuild
end
require 'chkbuild/options'
require 'chkbuild/target'
require 'chkbuild/title'
require "chkbuild/logfile"
require 'chkbuild/upload'

class ChkBuild::Build
  include Util

  def initialize(target, suffixes, depbuilds)
    @target = target
    @suffixes = suffixes
    @depbuilds = depbuilds

    @target_dir = ChkBuild.build_top + self.depsuffixed_name
    @public = ChkBuild.public_top + self.depsuffixed_name
    @public_log = @public+"log"
    @current_txt = @public+"current.txt"
  #p [:pid, $$, self.depsuffixed_name]
  end
  attr_reader :target, :suffixes, :depbuilds
  attr_reader :target_dir

  def suffixed_name
    name = @target.target_name.dup
    @suffixes.each {|suffix|
      name << '-' << suffix
    }
    name
  end

  def depsuffixed_name
    name = self.suffixed_name
    @depbuilds.each {|depbuild|
      name << '_' << depbuild.suffixed_name
    }
    name
  end

  def traverse_depbuild(&block)
    @depbuilds.each {|depbuild|
      yield depbuild
      depbuild.traverse_depbuild(&block)
    }
  end

  def sort_times(times)
    u, l = times.partition {|d| /Z\z/ =~ d }
    u.sort!
    l.sort!
    l + u # chkbuild used localtime at old time.
  end

  def build_time_sequence
    dirs = @target_dir.entries.map {|e| e.to_s }
    dirs.reject! {|d| /\A\d{8}T\d{6}Z?\z/ !~ d } # year 10000 problem
    sort_times(dirs)
  end

  def log_time_sequence
    return [] if !@public_log.directory?
    names = @public_log.entries.map {|e| e.to_s }
    result = []
    names.each {|n|
      result << $1 if /\A(\d{8}T\d{6}Z?)(?:\.log)?\.txt\.gz\z/ =~ n
    }
    sort_times(result)
  end

  ################

  def build
    dep_dirs = []
    @depbuilds.each {|depbuild|
      dep_dirs << "#{depbuild.target.target_name}=#{depbuild.dir}"
    }
    status = self.build_in_child(dep_dirs)
    status.to_i == 0
  end

  BuiltHash = {}

  def set_prebuilt_info(start_time_obj, start_time)
    BuiltHash[depsuffixed_name] = [start_time_obj, start_time]
  end

  def set_built_info(start_time_obj, start_time, status, dir, version)
    BuiltHash[depsuffixed_name] = [start_time_obj, start_time, status, dir, version]
  end

  def has_prebuilt_info?
    BuiltHash[depsuffixed_name] && 2 <= BuiltHash[depsuffixed_name].length
  end

  def has_built_info?
    BuiltHash[depsuffixed_name] && 5 <= BuiltHash[depsuffixed_name].length
  end

  def prebuilt_start_time_obj
    BuiltHash[depsuffixed_name][0].utc
  end

  def prebuilt_start_time
    BuiltHash[depsuffixed_name][1]
  end

  def built_status
    BuiltHash[depsuffixed_name][2]
  end

  def built_dir
    BuiltHash[depsuffixed_name][3]
  end

  def built_version
    BuiltHash[depsuffixed_name][4]
  end

  def build_in_child(dep_dirs)
    if has_built_info?
      raise "already built"
    end
    branch_info = @suffixes + dep_dirs
    t = Time.now.utc
    start_time_obj = Time.utc(t.year, t.month, t.day, t.hour, t.min, t.sec)
    start_time = start_time_obj.strftime("%Y%m%dT%H%M%SZ")
    set_prebuilt_info(start_time_obj, start_time)
    dir = ChkBuild.build_top + self.depsuffixed_name
    dir.mkpath
    dir += start_time
    dir.mkdir
    target_params_name = dir + "params.marshal"
    target_output_name = dir + "result.marshal"
    File.open(target_params_name, "wb") {|f| Marshal.dump([branch_info, ChkBuild::Build::BuiltHash], f) }
    ruby_command = RbConfig.ruby
    system(ruby_command, "-I#{ChkBuild::TOP_DIRECTORY}", $0, "internal-build", self.depsuffixed_name, start_time, target_params_name.to_s, target_output_name.to_s)
    status = $?
    str = File.open(target_output_name, "rb") {|f| f.read }
    begin
      version = Marshal.load(str)
    rescue ArgumentError
      version = self.suffixed_name
    end
    set_built_info(start_time_obj, start_time, status, dir, version)
    return status
  end

  def internal_build(start_time, target_params_name, target_output_name)
    #p [:internal_build, depsuffixed_name]
    branch_info, builthash = File.open(target_params_name) {|f| Marshal.load(f) }
    #pp builthash
    ChkBuild::Build::BuiltHash.update builthash
    self.build_and_exit(branch_info, start_time, target_output_name)
  end

  def build_and_exit(branch_info, start_time, target_output_name)
    if has_built_info?
    #p BuiltHash[depsuffixed_name]
      raise "already built: #{depsuffixed_name}"
    end
    dir = ChkBuild.build_top + self.depsuffixed_name + prebuilt_start_time
    marshal_data = ''
    if child_build_wrapper(target_output_name, nil, *branch_info)
      exit 0
    else
      exit 1
    end
  end

  def start_time
    return prebuilt_start_time if has_prebuilt_info?
    raise "#{self.suffixed_name}: no start_time yet"
  end

  def success?
    if has_built_info?
      if built_status.to_i == 0
        true
      else
        false
      end
    else
      nil
    end
  end

  def status
    return built_status if bulit_info
    raise "#{self.suffixed_name}: no status yet"
  end

  def dir
    return built_dir if has_built_info?
    raise "#{self.suffixed_name}: no dir yet"
  end

  def version
    return built_version if has_built_info?
    raise "#{self.suffixed_name}: no version yet"
  end

  def child_build_wrapper(target_output_name, parent_pipe, *branch_info)
    ret = ChkBuild.lock_puts(self.depsuffixed_name) {
      @errors = []
      child_build_target(target_output_name, *branch_info)
    }
    ret
  end

  def make_local_tmpdir
    tmpdir = @build_dir + 'tmp'
    tmpdir.mkdir(0700)
    ENV['TMPDIR'] = tmpdir.to_s
  end

  def child_build_target(target_output_name, *branch_info)
    opts = setup_build(target_output_name)
    @logfile.start_section 'start'
    ret = do_build(opts, branch_info)
    @logfile.start_section 'end'
    puts "elapsed #{format_elapsed_time(Time.now - prebuilt_start_time_obj)}"
    update_result
    @logfile.start_section 'end2'
    ret
  end

  def setup_build(target_output_name)
    opts = @target.opts
    @build_dir = @target_dir + prebuilt_start_time
    @log_filename = @build_dir + 'log'
    mkcd @target_dir
    @parent_pipe = File.open(target_output_name, "wb")
    Dir.chdir prebuilt_start_time
    @logfile = ChkBuild::LogFile.write_open(@log_filename, self)
    @logfile.change_default_output
    @public.mkpath
    @public_log.mkpath
    force_link "log", @current_txt
    make_local_tmpdir
    remove_old_build(prebuilt_start_time, opts.fetch(:old, ChkBuild.num_oldbuilds))
    opts
  end

  def do_build(opts, branch_info)
    ret = nil
    with_procmemsize(opts) {
      ret = catch_error { @target.build_proc.call(self, *branch_info) }
      output_status_section
    }
    ret
  end

  class LineReader
    def initialize(filename)
      @filename = filename
    end

    def each_line
      if /\.gz\z/ =~ @filename.to_s
        Zlib::GzipReader.wrap(open(@filename)) {|f|
          f.each_line {|line|
            line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
            yield line
          }
        }
      else
        open(@filename) {|f|
          f.each_line {|line|
            line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
            yield line
          }
        }
      end
    end
  end

  def update_result
    title, title_version = gen_title
    send_title_to_parent(title_version)
    force_link @current_txt, @public+'last.txt' if @current_txt.file?
    @t = prebuilt_start_time
    @compressed_rawlog_relpath = "log/#{@t}.log.txt.gz"
    @compressed_rawdiff_relpath = "log/#{@t}.diff.txt.gz"
    @compressed_loghtml_relpath = "log/#{@t}.log.html.gz"
    @compressed_diffhtml_relpath = "log/#{@t}.diff.html.gz"
    @rss_relpath = "rss"
    @public_uri = "#{ChkBuild.top_uri}#{u self.depsuffixed_name}/"
    compress_file(@log_filename, @public+@compressed_rawlog_relpath)
    @has_neterror = has_neterror?(@t)
    @older_time = find_diff_target_time(@t)
    @compressed_older_loghtml_relpath = @older_time ? "log/#{@older_time}.log.html.gz" : nil
    @compressed_older_diffhtml_relpath = @older_time ? "log/#{@older_time}.diff.html.gz" : nil
    different_sections = make_diff(@older_time, @t)
    @diff_reader = LineReader.new(@public+@compressed_rawdiff_relpath)
    @log_reader = LineReader.new(@log_filename)
    update_summary(title, different_sections)
    update_recent
    make_last_html(title, different_sections, @public+"last.html")
    compress_file(@public+"last.html", @public+"last.html.gz")
    make_loghtml(title, different_sections)
    make_diffhtml(title, different_sections)
    make_rss(title, different_sections)
    update_older_page if @older_time && !@has_neterror
    ChkBuild.run_upload_hooks(self.suffixed_name)
  end

  def update_older_page
    block = lambda {|src, dst|
      src.each_line {|line|
        line = line.gsub(/<!--placeholder_start-->(?:nextdiff|newerdiff|NewerDiff)<!--placeholder_end-->/) {
	  "<a href=#{ha "../"+@compressed_diffhtml_relpath }>NewerDiff</a>"
	}
        line = line.gsub(/<!--placeholder_start-->(?:nextlog|newerlog|NewerLog)<!--placeholder_end-->/) {
	  "<a href=#{ha "../"+@compressed_loghtml_relpath }>#{@t}</a>"
	}
	dst.print line
      }
    }
    update_gziped_file(@public+@compressed_older_loghtml_relpath, &block)
    update_gziped_file(@public+@compressed_older_diffhtml_relpath, &block)
  end

  def update_gziped_file(filename)
    atomic_make_compressed_file(filename) {|dst|
      Zlib::GzipReader.wrap(open(filename)) {|src|
	yield src, dst
      }
    }
  end

  def gen_title
    titlegen = ChkBuild::Title.new(@target, @logfile)
    title_succ = catch_error('run_hooks') { titlegen.run_hooks }
    title = titlegen.make_title
    title << " (titlegen.run_hooks error)" if !title_succ
    title_version = titlegen.version
    return title, title_version
  end

  def send_title_to_parent(title_version)
    if @parent_pipe
      Marshal.dump(title_version, @parent_pipe)
      @parent_pipe.close
    end
  end

  attr_reader :logfile

  def with_procmemsize(opts)
    if opts[:procmemsize]
      current_pid = $$
      IO.popen("procmemsize -p #{current_pid}", "w") {|io|
        procmemsize_pid = io.pid
        ret = yield
        Process.kill :TERM, procmemsize_pid
      }
    else
      ret = yield
    end
    ret
  end

  def output_status_section
    @logfile.start_section 'success' if @errors.empty?
  end

  def catch_error(name=nil)
    err = nil
    begin
      yield
    rescue Exception => err
    end
    return true unless err
    @errors << err
    @logfile.start_section("#{name} error") if name
    show_backtrace err unless CommandError === err
    GDB.check_core(@build_dir)
    if CommandError === err
      puts "failed(#{err.reason})"
    else
      if err.respond_to? :reason
        puts "failed(#{err.reason} #{err.class})"
      else
        puts "failed(#{err.class})"
      end
    end
    return false
  end

  def network_access(name=nil)
    begin
      yield
    ensure
      if err = $!
        @logfile.start_section("neterror")
      end
    end
  end

  def build_dir() @build_dir end

  def remove_old_build(current, num)
    dirs = build_time_sequence
    dirs.delete current
    return if dirs.length <= num
    dirs[-num..-1] = []
    dirs.each {|d|
      (@target_dir+d).rmtree
    }
  end

  def update_summary(title, different_sections)
    start_time = prebuilt_start_time
    if different_sections
      if different_sections.empty?
        diff_txt = "diff"
      else
	different_sections = different_sections.map {|secname| secname.sub(%r{/.*\z}, "/") }.uniq
        diff_txt = "diff:#{different_sections.join(',')}"
      end
    end
    open(@public+"summary.txt", "a") {|f|
      f.print "#{start_time} #{title}"
      f.print " (#{diff_txt})" if diff_txt
      f.puts
    }
    open(@public+"summary.html", "a") {|f|
      if f.stat.size == 0
        f.puts "<title>#{h self.depsuffixed_name} build summary</title>"
        f.puts "<h1>#{h self.depsuffixed_name} build summary</h1>"
        f.puts "<p><a href=\"../\">chkbuild</a></p>"
      end
      f.print "<a href=#{ha @compressed_loghtml_relpath} name=#{ha start_time}>#{h start_time}</a> #{h title}"
      if diff_txt
        f.print " (<a href=#{ha @compressed_diffhtml_relpath}>#{h diff_txt}</a>)"
      else
        f.print " (<a href=#{ha @compressed_diffhtml_relpath}>no diff</a>)"
      end
      f.puts "<br>"
    }
  end

  RECENT_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
    <link rel="alternate" type="application/rss+xml" title="RSS" href=<%=ha @public_uri+@rss_relpath %>>
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href="../">chkbuild</a>
      <a href="summary.html">summary</a>
      <a href="recent.html">recent</a>
      <a href="last.html.gz">last</a>
    </p>
<%= recent_summary.chomp %>
    <hr>
    <p>
      <a href="../">chkbuild</a>
      <a href="summary.html">summary</a>
      <a href="recent.html">recent</a>
      <a href="last.html.gz">last</a>
    </p>
  </body>
</html>
End

  def update_recent
    start_time = prebuilt_start_time
    summary_path = @public+"summary.html"
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
    title = "#{self.depsuffixed_name} recent build summary (#{Util.simple_hostname})"

    recent_summary = lines.reverse.join
    content = ERB.new(RECENT_HTMLTemplate).result(binding)

    recent_path = @public+"recent.html"
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
    str.gsub(/[^\t\r\n -~]+/) {|invalid|
      "[" + invalid.unpack("H*")[0] + "]"
    }
  end

  def markup_log_line(line)
    line = encode_invalid(line)
    result = ''
    if /\A== (\S+)/ =~ line
      tag = $1
      rest = $'
      result << "<a name=#{ha(u(tag))}>== #{h(tag)}</a>#{h(rest)}"
    else
      i = 0
      line.scan(/#{URI.regexp(['http'])}/o) {
        result << h(line[i...$~.begin(0)]) if i < $~.begin(0)
        result << "<a href=#{ha $&}>#{h $&}</a>"
        i = $~.end(0)
      }
      result << h(line[i...line.length]) if i < line.length
    end
    result
  end

  def markup_log(str)
    result = ''
    str.each_line {|line|
      result << markup_log_line(line)
    }
    result
  end

  def markup_diff_line(line)
    line = encode_invalid(line)
    if %r{\A((?:OLDREV|NEWREV|CHG|ADD|DEL|COMMIT) .*)\s(http://\S*)\s*\z} =~ line
      content = $1
      url = $2
      "<a href=#{ha url}>#{h content.strip}</a>"
    else
      result = ''
      i = 0
      line.scan(/#{URI.regexp(['http'])}/o) {
	result << h(line[i...$~.begin(0)]) if i < $~.begin(0)
	result << "<a href=#{ha $&}>#{h $&}</a>"
	i = $~.end(0)
      }
      result << h(line[i...line.length]) if i < line.length
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

  LAST_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
    <link rel="alternate" type="application/rss+xml" title="RSS" href=<%=ha @public_uri+@rss_relpath %>>
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href="../">chkbuild</a>
      <a href="summary.html">summary</a>
      <a href="recent.html">recent</a>
      <a href="last.html.gz">last</a>
      <a href=<%=ha @compressed_diffhtml_relpath %>>permalink</a>
      <a href=<%=ha @compressed_loghtml_relpath %>>fulllog</a>
    </p>
    <p>
% if @older_time
      <a href=<%=ha @compressed_older_diffhtml_relpath %>>OlderDiff</a> &lt;
      <a href=<%=ha @compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
% end
      <a href=<%=ha @compressed_diffhtml_relpath %>>ThisDiff</a> &gt;
      <a href=<%=ha @compressed_loghtml_relpath %>><%=h @t %></a>
    </p>
% if has_diff
    <pre>
%     @diff_reader.each_line {|line|
<%=     markup_diff_line line.chomp %>
%     }
    </pre>
% else
    <p>no differences</p>
% end
    <p>
% if @older_time
      <a href=<%=ha @compressed_older_diffhtml_relpath %>>OlderDiff</a> &lt;
      <a href=<%=ha @compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
% end
      <a href=<%=ha @compressed_diffhtml_relpath %>>ThisDiff</a> &gt;
      <a href=<%=ha @compressed_loghtml_relpath %>><%=h @t %></a>
    </p>
    <hr>
    <p>
      <a href="../">chkbuild</a>
      <a href="summary.html">summary</a>
      <a href="recent.html">recent</a>
      <a href="last.html.gz">last</a>
      <a href=<%=ha @compressed_diffhtml_relpath %>>permalink</a>
      <a href=<%=ha @compressed_loghtml_relpath %>>fulllog</a>
    </p>
  </body>
</html>
End

  def make_last_html(title, has_diff, dst)
    atomic_make_file(dst) {|_erbout|
      ERBIO.new(LAST_HTMLTemplate, nil, '%').result(binding)
    }
  end

  DIFF_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
    <link rel="alternate" type="application/rss+xml" title="RSS" href=<%=ha @public_uri+@rss_relpath %>>
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href="../../">chkbuild</a>
      <a href="../summary.html">summary</a>
      <a href="../recent.html">recent</a>
      <a href="../last.html.gz">last</a>
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>difference</a>
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>>fulllog</a>
    </p>
    <p>
% if @older_time
      <a href=<%=ha "../"+@compressed_older_diffhtml_relpath %>>OlderDiff</a> &lt;
      <a href=<%=ha "../"+@compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
% end
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>ThisDiff</a> &gt;
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>><%=h @t %></a> &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end-->
    </p>
% if has_diff
    <pre>
%     @diff_reader.each_line {|line|
<%=     markup_diff_line line.chomp %>
%     }
    </pre>
% else
    <p>no differences</p>
% end
    <p>
% if @older_time
      <a href=<%=ha "../"+@compressed_older_diffhtml_relpath %>>OlderDiff</a> &lt;
      <a href=<%=ha "../"+@compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
% end
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>ThisDiff</a> &gt;
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>><%=h @t %></a> &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end-->
    </p>
    <hr>
    <p>
      <a href="../../">chkbuild</a>
      <a href="../summary.html">summary</a>
      <a href="../recent.html">recent</a>
      <a href="../last.html.gz">last</a>
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>difference</a>
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>>fulllog</a>
    </p>
  </body>
</html>
End

  def make_diffhtml(title, has_diff)
    atomic_make_compressed_file(@public+@compressed_diffhtml_relpath) {|_erbout|
      ERBIO.new(DIFF_HTMLTemplate, nil, '%').result(binding)
    }
  end

  LOG_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%=h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
    <link rel="alternate" type="application/rss+xml" title="RSS" href=<%=ha @public_uri+@rss_relpath %>>
  </head>
  <body>
    <h1><%=h title %></h1>
    <p>
      <a href="../../">chkbuild</a>
      <a href="../summary.html">summary</a>
      <a href="../recent.html">recent</a>
      <a href="../last.html.gz">last</a>
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>difference</a>
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>>fulllog</a>
    </p>
    <p>
% if @older_time
      <a href=<%=ha "../"+@compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>OlderDiff</a> &lt;
% end
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>><%=h @t %></a> &gt;
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
      <a href=<%=ha "../"+@compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>OlderDiff</a> &lt;
% end
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>><%=h @t %></a> &gt;
      <!--placeholder_start-->NewerDiff<!--placeholder_end--> &gt;
      <!--placeholder_start-->NewerLog<!--placeholder_end-->
    </p>
    <hr>
    <p>
      <a href="../../">chkbuild</a>
      <a href="../summary.html">summary</a>
      <a href="../recent.html">recent</a>
      <a href="../last.html.gz">last</a>
      <a href=<%=ha "../"+@compressed_diffhtml_relpath %>>difference</a>
      <a href=<%=ha "../"+@compressed_loghtml_relpath %>>fulllog</a>
    </p>
  </body>
</html>
End

  def make_loghtml(title, has_diff)
    atomic_make_compressed_file(@public+@compressed_loghtml_relpath) {|_erbout|
      ERBIO.new(LOG_HTMLTemplate, nil, '%').result(binding)
    }
  end

  RSS_CONTENT_HTMLTemplate = <<'End'
<p>
% if @older_time
  <a href=<%=ha @public_uri+@compressed_older_diffhtml_relpath %>>OlderDiff</a> &lt;
  <a href=<%=ha @public_uri+@compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
% end
  <a href=<%=ha @public_uri+@compressed_diffhtml_relpath %>>ThisDiff</a> &gt;
  <a href=<%=ha @public_uri+@compressed_loghtml_relpath %>><%=h @t %></a>
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
<p><a href=<%=ha @public_uri+@compressed_diffhtml_relpath %>>read more differences</a></p>
%   end
% else
<p>no differences</p>
% end
<p><a href=<%=ha @public_uri+@compressed_loghtml_relpath %>>full log</a></p>
<p>
% if @older_time
  <a href=<%=ha @public_uri+@compressed_older_diffhtml_relpath %>>OlderDiff</a> &lt;
  <a href=<%=ha @public_uri+@compressed_older_loghtml_relpath %>><%=h @older_time %></a> &lt;
% end
  <a href=<%=ha @public_uri+@compressed_diffhtml_relpath %>>ThisDiff</a> &gt;
  <a href=<%=ha @public_uri+@compressed_loghtml_relpath %>><%=h @t %></a>
</p>
End

  def make_rss_html_content(title, has_diff)
    max_diff_lines = 500
    ERB.new(RSS_CONTENT_HTMLTemplate, nil, '%').result(binding)
  end

  def make_rss(title, has_diff)
    latest_url = "#{ChkBuild.top_uri}#{u self.depsuffixed_name}/#{@compressed_diffhtml_relpath}"
    t = prebuilt_start_time_obj
    if (@public+@rss_relpath).exist?
      rss = RSS::Parser.parse((@public+@rss_relpath).read)
      olditems = rss.items
      n = 24
      if n < olditems.length
        olditems = olditems.sort_by {|item| item.date }[-n,n]
      end
    else
      olditems = []
    end
    rss = RSS::Maker.make("1.0") {|maker|
      maker.channel.about = @public_uri+@rss_relpath
      maker.channel.title = "#{self.depsuffixed_name} (#{Util.simple_hostname})"
      maker.channel.description = "chkbuild #{self.depsuffixed_name}"
      maker.channel.link = "#{ChkBuild.top_uri}#{u self.depsuffixed_name}/"
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
        item.date = t
        item.content_encoded = make_rss_html_content(title, has_diff)
      }
    }
    atomic_make_file(@public+@rss_relpath) {|f| f.puts rss.to_s }
  end

  def compress_file(src, dst)
    Zlib::GzipWriter.wrap(open(dst, "w")) {|z|
      open(src) {|f|
        FileUtils.copy_stream(f, z)
      }
    }
  end

  def show_backtrace(err=$!)
    puts "|#{err.message} (#{err.class})"
    err.backtrace.each {|pos| puts "| #{pos}" }
  end

  def has_neterror?(time)
    open_gziped_log(time) {|f|
      f.each_line {|line|
	line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
	if /\A== neterror / =~ line
	  return true
	end
      }
    }
    false
  end

  def find_diff_target_time(time2)
    entries = Dir.entries(@public_log)
    time_seq = []
    entries.each {|f|
      if /\A(\d{8}T\d{6}Z?)(?:\.log)?\.txt\.gz\z/ =~ f # year 10000 problem
        time_seq << $1
      end
    }
    time_seq = sort_times(time_seq)
    time_seq.delete time2
    while !time_seq.empty? && has_neterror?(time_seq.last)
      time_seq.pop
    end
    time_seq.last
  end

  def make_diff(time1, time2)
    output_path = @public+@compressed_rawdiff_relpath
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
    has_diff = has_change_line | Lchg.diff(tmp1.path, tmp2.path, out, header1, header2)
    return nil if !has_diff
    ret = []
    ret << 'src' if has_change_line
    ret.concat different_sections(tmp1, tmp2)
    ret 
  end

  def output_change_lines(t2, out)
    has_diff = false
    open_gziped_log(t2) {|f|
      has_change_line = false
      f.each {|line|
        if ChkBuild::Target::CHANGE_LINE_PAT =~ line
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

  def output_change_lines2(t1, t2, out)
    has_change_line = false
    a1 = collect_checkout_log(t1)
    h1 = {}
    a1.each {|lines| h1[lines[0]] = lines }
    a2 = collect_checkout_log(t2)
    h2 = {}
    a2.each {|lines| h2[lines[0]] = lines }
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
	    self.send(meth, lines1, lines2, out)
	  else
	    out.puts "CHG #{checkout_line}"
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

  def different_sections(tmp1, tmp2)
    logfile1 = ChkBuild::LogFile.read_open(tmp1.path)
    logfile2 = ChkBuild::LogFile.read_open(tmp2.path)
    secnames1 = logfile1.secnames
    secnames2 = logfile2.secnames
    different_sections = secnames1 - secnames2
    secnames2.each {|secname|
      if !secnames1.include?(secname)
        different_sections << secname
      elsif logfile1.section_size(secname) != logfile2.section_size(secname)
        different_sections << secname
      elsif logfile1.get_section(secname) != logfile2.get_section(secname)
        different_sections << secname
      end
    }
    different_sections
  end

  def make_diff_content(time)
    times = [time]
    uncompressed = Tempfile.open("#{time}.u.")
    open_gziped_log(time) {|z|
      FileUtils.copy_stream(z, uncompressed)
    }
    uncompressed.flush
    logfile = ChkBuild::LogFile.read_open(uncompressed.path)
    logfile.dependencies.each {|dep_suffixed_name, dep_time, dep_version|
      times << dep_time
    }
    pat = Regexp.union(*times.uniq)
    tmp = Tempfile.open("#{time}.d.")
    state = {}
    open_gziped_log(time) {|z|
      z.each_line {|line|
        line = line.gsub(pat, '<buildtime>')
        @target.each_diff_preprocess_hook {|block|
          catch_error(block.to_s) { line = block.call(line, state) }
        }
        tmp << line
      }
    }
    tmp.flush
    tmp
  end

  def sort_diff_content(time1, tmp1, time2, tmp2)
    pat = @target.diff_preprocess_sort_pattern
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

  def open_gziped_log(time, &block)
    if File.file?(@public_log+"#{time}.log.txt.gz")
      filename = @public_log+"#{time}.log.txt.gz"
    else
      filename = @public_log+"#{time}.txt.gz"
    end
    Zlib::GzipReader.wrap(open(filename), &block)
  end

  class CommandError < StandardError
    def initialize(status, reason, message=reason)
      super message
      @reason = reason
      @status = status
    end

    attr_accessor :reason
  end
  def run(command, *args, &block)
    opts = @target.opts.dup
    opts.update args.pop if Hash === args.last

    if opts.include?(:section)
      secname = opts[:section]
    else
      secname = opts[:reason] || File.basename(command)
    end
    @logfile.start_section(secname) if secname

    if !opts.include?(:output_interval_timeout)
      opts[:output_interval_timeout] = '10min'
    end

    separated_stderr = nil
    if opts[:stderr] == :separate
      separated_stderr = Tempfile.new("chkbuild")
      opts[:stderr] = separated_stderr.path
    end

    alt_commands = opts.fetch(:alt_commands, [])

    commands = [command, *alt_commands]
    commands.reject! {|c|
      ENV["PATH"].split(/:/).all? {|d|
        f = File.join(d, c)
	!File.file?(f) || !File.executable?(f)
      }
    }
    if !commands.empty?
      command, *alt_commands = commands
    end

    puts "+ #{Escape.shell_command [command, *args]}"
    pos = STDOUT.pos
    ruby_script = script_to_run_in_child(opts, command, alt_commands, *args)
    begin
      command_status = TimeoutCommand.timeout_command(ruby_script, opts.fetch(:timeout, '1h'), STDERR, opts)
    ensure
      exc = $!
      if exc && secname
        class << exc
          attr_accessor :reason
        end
        exc.reason = secname
      end
    end
    if separated_stderr
      separated_stderr.rewind
      if separated_stderr.size != 0
        puts "stderr:"
	FileUtils.copy_stream(separated_stderr, STDOUT)
	separated_stderr.close(true)
      end
    end
    begin
      if command_status.exitstatus != 0
        if command_status.exited?
          puts "exit #{command_status.exitstatus}"
        elsif command_status.signaled?
          puts "signal #{SignalNum2Name[command_status.termsig]} (#{command_status.termsig})"
        elsif command_status.stopped?
          puts "stop #{SignalNum2Name[command_status.stopsig]} (#{command_status.stopsig})"
        else
          p command_status
        end
        raise CommandError.new(command_status, opts.fetch(:section, command))
      end
    end
  end

  def script_to_run_in_child(opts, command, alt_commands, *args)
    ruby_script = ''
    opts.each {|k, v|
      next if /\AENV:/ !~ k.to_s
      k = $'
      ruby_script << "ENV[#{k.dump}] = #{v.dump}\n"
    }

    if Process.respond_to? :setrlimit
      limit = ChkBuild.get_limit
      opts.each {|k, v|
        limit[$'.intern] = v if /\Ar?limit_/ =~ k.to_s
      }
      ruby_script << <<-"End"
        def resource_unlimit(resource)
          if Symbol === resource
            begin
              resource = Process.const_get(resource)
            rescue NameError
              return
            end
          end
          cur_limit, max_limit = Process.getrlimit(resource)
          Process.setrlimit(resource, max_limit, max_limit)
        end

        def resource_limit(resource, val)
          if Symbol === resource
            begin
              resource = Process.const_get(resource)
            rescue NameError
              return
            end
          end
          cur_limit, max_limit = Process.getrlimit(resource)
          if max_limit < val
            val = max_limit
          end
          Process.setrlimit(resource, val, val)
        end

        resource_unlimit(:RLIMIT_CORE)
        resource_limit(:RLIMIT_CPU, #{limit.fetch(:cpu).to_i})
        resource_limit(:RLIMIT_STACK, #{limit.fetch(:stack).to_i})
        resource_limit(:RLIMIT_DATA, #{limit.fetch(:data).to_i})
        resource_limit(:RLIMIT_AS, #{limit.fetch(:as).to_i})
      End
    end

    if opts.include?(:stdout)
      ruby_script << "STDOUT.reopen(#{opts[:stdout].dump}, 'w')\n"
    end
    if opts.include?(:stderr)
      ruby_script << "STDERR.reopen(#{opts[:stderr].dump}, 'w')\n"
    end

    ruby_script << "command = #{command.dump}\n"
    ruby_script << "args = [#{args.map {|s| s.dump }.join(",")}]\n"
    ruby_script << "alt_commands = [#{alt_commands.map {|s| s.dump }.join(",")}]\n"

    ruby_script + <<-"End"
    begin
      exec [command, command], *args
    rescue Errno::ENOENT
      if !alt_commands.empty?
        command = alt_commands.shift
        retry
      else
        raise
      end
    end
    End
  end

  SignalNum2Name = Hash.new('unknown signal')
  Signal.list.each {|name, num| SignalNum2Name[num] = "SIG#{name}" }

  def make(*args)
    opts = {}
    opts = args.pop if Hash === args.last
    opts = opts.dup
    opts[:alt_commands] = ['make']

    make_opts, targets = args.partition {|a| /=/ =~ a }
    if targets.empty?
      opts[:section] ||= 'make'
      self.run("gmake", *(make_opts + [opts]))
    else
      targets.each {|target|
        h = opts.dup
        h[:reason] = target
        h[:section] ||= target
        self.run("gmake", target, *(make_opts + [h]))
      }
    end
  end
end
