# Copyright (C) 2006,2007,2008,2009 Tanaka Akira  <akr@fsij.org>
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
require "erb"
include ERB::Util
require "uri"
require "tempfile"
require "pathname"

require 'escape'
require 'timeoutcom'
require 'gdb'
require "udiff"
require "util"

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

  def build_time_sequence
    dirs = @target_dir.entries.map {|e| e.to_s }
    dirs.reject! {|d| /\A\d{8}T\d{6}\z/ !~ d } # year 10000 problem
    dirs.sort!
    dirs
  end

  def log_time_sequence
    return [] if !@public_log.directory?
    names = @public_log.entries.map {|e| e.to_s }
    result = []
    names.each {|n|
      result << $1 if /\A(\d{8}T\d{6})(?:\.log)?\.txt\.gz\z/ =~ n
    }
    result.sort!
    result
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

  def build_in_child(dep_dirs)
    if defined? @built_status
      raise "already built"
    end
    branch_info = @suffixes + dep_dirs
    start_time_obj = Time.now
    @start_time = start_time_obj.strftime("%Y%m%dT%H%M%S")
    dir = ChkBuild.build_top + self.depsuffixed_name + @start_time
    r, w = IO.pipe
    r.close_on_exec = true
    w.close_on_exec = true
    pid = fork {
      r.close
      if child_build_wrapper(w, *branch_info)
        exit 0
      else
        exit 1
      end
    }
    w.close
    str = r.read
    r.close
    status = Process.wait2(pid)[1]
    begin
      version = Marshal.load(str)
    rescue ArgumentError
      version = self.suffixed_name
    end
    @built_status = status
    @built_dir = dir
    @built_version = version
    return status
  end

  def start_time
    return @start_time if defined? @start_time
    raise "#{self.suffixed_name}: no start_time yet"
  end

  def success?
    if defined? @built_status
      if @built_status.to_i == 0
        true
      else
        false
      end
    else
      nil
    end
  end

  def status
    return @built_status if defined? @built_status
    raise "#{self.suffixed_name}: no status yet"
  end

  def dir
    return @built_dir if defined? @built_dir
    raise "#{self.suffixed_name}: no dir yet"
  end

  def version
    return @built_version if defined? @built_version
    raise "#{self.suffixed_name}: no version yet"
  end

  def child_build_wrapper(parent_pipe, *branch_info)
    ret = ChkBuild.lock_puts(self.depsuffixed_name) {
      @parent_pipe = parent_pipe
      @errors = []
      child_build_target(*branch_info)
    }
    ret
  end

  def make_local_tmpdir
    tmpdir = @build_dir + 'tmp'
    tmpdir.mkpath
    ENV['TMPDIR'] = tmpdir.to_s
  end

  def child_build_target(*branch_info)
    opts = @target.opts
    @build_dir = @target_dir + @start_time
    @log_filename = @build_dir + 'log'
    mkcd @target_dir
    raise "already exist: #{@start_time}" if File.exist? @start_time
    Dir.mkdir @start_time # fail if it is already exists.
    Dir.chdir @start_time
    @logfile = ChkBuild::LogFile.write_open(@log_filename, self)
    @logfile.change_default_output
    @public.mkpath
    @public_log.mkpath
    force_link "log", @current_txt
    make_local_tmpdir
    remove_old_build(@start_time, opts.fetch(:old, ChkBuild.num_oldbuilds))
    @logfile.start_section 'start'
    ret = nil
    with_procmemsize(opts) {
      ret = catch_error { @target.build_proc.call(self, *branch_info) }
      output_status_section
      @logfile.start_section 'end'
    }
    force_link @current_txt, @public+'last.txt' if @current_txt.file?
    titlegen = ChkBuild::Title.new(@target, @logfile)
    title_succ = catch_error('run_hooks') { titlegen.run_hooks }
    title = titlegen.make_title
    title << " (titlegen.run_hooks error)" if !title_succ
    Marshal.dump(titlegen.version, @parent_pipe)
    @parent_pipe.close
    @compressed_log_basename = "#{@start_time}.log.txt.gz"
    @compressed_diff_basename = "#{@start_time}.diff.txt.gz"
    compress_file(@log_filename, @public_log+@compressed_log_basename)
    different_sections = make_diff
    update_summary(title, different_sections)
    update_recent
    make_html_log(@log_filename, title, different_sections, @public+"last.html")
    compress_file(@public+"last.html", @public+"last.html.gz")
    ChkBuild.run_upload_hooks(self.suffixed_name)
    ret
  end

  attr_reader :logfile

  def with_procmemsize(opts)
    if opts[:procmemsize]
      current_pid = $$
      procmemsize_pid = fork { exec *%W[procmemsize -p #{current_pid}] }
      ret = yield
      Process.kill :TERM, procmemsize_pid
      Process.wait procmemsize_pid
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
    start_time = @start_time
    if different_sections
      if different_sections.empty?
        diff_txt = "diff"
      else
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
      f.print "<a href=\"log/#{h @compressed_log_basename}\" name=\"#{start_time}\">#{h start_time}</a> #{h title}"
      f.print " (<a href=\"log/#{h @compressed_diff_basename}\">#{h diff_txt}</a>)" if diff_txt
      f.puts "<br>"
    }
  end

  RECENT_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%= h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
  </head>
  <body>
    <h1><%= h title %></h1>
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
    start_time = @start_time
    summary_path = @public+"summary.html"
    lines = []
    summary_path.open {|f|
      while l = f.gets
        lines << l
        lines.shift if 10 < lines.length
      end
    }
    while !lines.empty? && /\A<a / !~ lines[0]
      lines.shift
    end
    title = "#{self.depsuffixed_name} recent build summary"

    recent_summary = lines.reverse.join
    content = ERB.new(RECENT_HTMLTemplate).result(binding)

    recent_path = @public+"recent.html"
    atomic_make_file(recent_path, content)
  end

  def markup(str)
    result = ''
    i = 0
    str.scan(/#{URI.regexp(['http'])}/o) {
      result << h(str[i...$~.begin(0)]) if i < $~.begin(0)
      result << "<a href=\"#{h $&}\">#{h $&}</a>"
      i = $~.end(0)
    }
    result << h(str[i...str.length]) if i < str.length
    result
  end

  LAST_HTMLTemplate = <<'End'
<html>
  <head>
    <title><%= h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
  </head>
  <body>
    <h1><%= h title %></h1>
    <p>
      <a href="../">chkbuild</a>
      <a href="summary.html">summary</a>
      <a href="recent.html">recent</a>
      <a href="<%=h permalink %>">permalink</a>
% if has_diff
      <a href="<%=h diff_permalink %>">diff</a>
% end
    </p>
    <pre><%= markup log %></pre>
    <hr>
    <p>
      <a href="../">chkbuild</a>
      <a href="summary.html">summary</a>
      <a href="recent.html">recent</a>
      <a href="<%=h permalink %>">permalink</a>
% if has_diff
      <a href="<%=h diff_permalink %>">diff</a>
% end
    </p>
  </body>
</html>
End

  def make_html_log(log_filename, title, has_diff, dst)
    log = File.read(log_filename)
    log.force_encoding("ascii-8bit") if log.respond_to? :force_encoding
    permalink = "log/#{@compressed_log_basename}"
    diff_permalink = "log/#{@compressed_diff_basename}"
    content = ERB.new(LAST_HTMLTemplate, nil, '%').result(binding)
    atomic_make_file(dst, content)
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

  def make_diff
    time2 = @start_time
    entries = Dir.entries(@public_log)
    time_seq = []
    entries.each {|f|
      if /\A(\d{8}T\d{6})(?:\.log)?\.txt\.gz\z/ =~ f # year 10000 problem
        time_seq << $1
      end
    }
    time_seq.sort!
    time_seq.delete time2
    while !time_seq.empty? &&
          open_gziped_log(time_seq.last) {|f|
            neterror = false
            f.each_line {|line|
              line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
              if /\A== neterror / =~ line
                neterror = true
                break
              end
            }
            if neterror
              true
            else
              false
            end
          }
      time_seq.pop
    end
    return nil if time_seq.empty?
    time1 = time_seq.last
    different_sections = nil
    output_path = @public_log+@compressed_diff_basename
    Zlib::GzipWriter.wrap(open(output_path, "w")) {|z|
      different_sections = output_diff(time1, time2, z)
    }
    if !different_sections
      output_path.unlink
      return nil
    end
    return different_sections
  end

  def output_diff(t1, t2, out)
    has_change_line = output_change_lines(t2, out)
    tmp1 = make_diff_content(t1)
    tmp2 = make_diff_content(t2)
    tmp1, tmp2 = sort_diff_content(t1, tmp1, t2, tmp2)
    header = "--- #{t1}\n+++ #{t2}\n"
    has_diff = has_change_line | UDiff.diff(tmp1.path, tmp2.path, out, header)
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
    open_gziped_log(time) {|z|
      z.each_line {|line|
        line = line.gsub(pat, '<buildtime>')
        @target.each_diff_preprocess_hook {|block|
          catch_error(block.to_s) { line = block.call(line) }
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

    puts "+ #{Escape.shell_command [command, *args]}"
    pos = STDOUT.pos
    begin
      command_status = TimeoutCommand.timeout_command(opts.fetch(:timeout, '1h'), STDERR, opts) {
        run_in_child(opts, command, *args)
      }
    ensure
      exc = $!
      if exc && secname
        class << exc
          attr_accessor :reason
        end
        exc.reason = secname
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

  def run_in_child(opts, command, *args)
    opts.each {|k, v|
      next if /\AENV:/ !~ k.to_s
      ENV[$'] = v
    }
    if Process.respond_to? :setrlimit
      resource_unlimit(:RLIMIT_CORE)
      limit = ChkBuild.get_limit
      opts.each {|k, v| limit[$'.intern] = v if /\Ar?limit_/ =~ k.to_s }
      resource_limit(:RLIMIT_CPU, limit.fetch(:cpu))
      resource_limit(:RLIMIT_STACK, limit.fetch(:stack))
      resource_limit(:RLIMIT_DATA, limit.fetch(:data))
      resource_limit(:RLIMIT_AS, limit.fetch(:as))
      #system('sh', '-c', "ulimit -a")
    end
    alt_commands = opts.fetch(:alt_commands, [])
    if opts.include?(:stdout)
      STDOUT.reopen(opts[:stdout], "w")
    end
    if opts.include?(:stderr)
      STDERR.reopen(opts[:stderr], "w")
    end
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
