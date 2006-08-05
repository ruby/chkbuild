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
require 'chkbuild/target'
require 'chkbuild/title'
require "chkbuild/logfile"

class ChkBuild::Build
  include Util

  def initialize(target, suffixes, depbuilds)
    @target = target
    @suffixes = suffixes
    @depbuilds = depbuilds

    @target_dir = "#{ChkBuild.build_dir}/#{self.depsuffixed_name}"
    @public = "#{ChkBuild.public_dir}/#{self.depsuffixed_name}"
    @public_log = "#{@public}/log"
    @current_txt = "#{@public}/current.txt"
  end
  attr_reader :target, :suffixes, :depbuilds

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

  def add_title_hook(secname, &block) @target.add_title_hook(secname, &block) end

  def build
    dep_dirs = []
    dep_versions = []
    @depbuilds.each {|depbuild|
      dep_dirs << "#{depbuild.target.target_name}=#{depbuild.dir}"
      dep_versions.concat depbuild.version_list
    }
    status = self.build_in_child(dep_versions, dep_dirs)
    status.to_i == 0
  end

  def build_in_child(dep_versions, dep_dirs)
    if defined? @child_status
      raise "already built"
    end
    branch_info = @suffixes + dep_dirs
    start_time_obj = Time.now
    dir = "#{ChkBuild.build_dir}/#{self.depsuffixed_name}/#{start_time_obj.strftime("%Y%m%dT%H%M%S")}"
    r, w = IO.pipe
    r.close_on_exec = true
    w.close_on_exec = true
    pid = fork {
      r.close
      if child_build_wrapper(w, start_time_obj, dep_versions, *branch_info)
        exit 0
      else
        exit 1
      end
    }
    w.close
    str = r.read
    r.close
    Process.wait(pid)
    status = $?
    begin
      version_list = Marshal.load(str)
    rescue ArgumentError
      version_list = []
    end
    @child_status = status
    @child_dir = dir
    @child_version_list = version_list
    return status
  end

  def success?
    if defined? @child_status
      if @child_status.to_i == 0
        true
      else
        false
      end
    else
      nil
    end
  end

  def status
    return @child_status if defined? @child_status
    raise "#{self.suffixed_name}: no status yet"
  end

  def dir
    return @child_dir if defined? @child_dir
    raise "#{self.suffixed_name}: no dir yet"
  end

  def version_list
    return @child_version_list if defined? @child_version_list
    raise "#{self.suffixed_name}: no version_list yet"
  end

  def child_build_wrapper(parent_pipe, start_time_obj, dep_versions, *branch_info)
    Build.lock_puts self.depsuffixed_name
    @parent_pipe = parent_pipe
    success = false
    begin
      child_build_target(start_time_obj, dep_versions, *branch_info)
      success = true
    rescue CommandError
    end
    success
  end

  def child_build_target(start_time_obj, dep_versions, *branch_info)
    opts = @target.opts
    @start_time = start_time_obj.strftime("%Y%m%dT%H%M%S")
    @dir = "#{@target_dir}/#{@start_time}"
    @log_filename = "#{@dir}/log"
    mkcd @target_dir
    raise "already exist: #{@start_time}" if File.exist? @start_time
    Dir.mkdir @start_time # fail if it is already exists.
    Dir.chdir @start_time

    @logfile = ChkBuild::LogFile.write_open(@log_filename,
      @target.target_name, @suffixes,
      @depbuilds.map {|db| db.suffixed_name },
      @depbuilds.map {|db| db.version_list }.flatten)
    Thread.current[:logfile] = @logfile
    @logfile.change_default_output

    success = false
    FileUtils.mkpath(@public)
    FileUtils.mkpath(@public_log)
    careful_link "log", @current_txt
    remove_old_build(@start_time, opts.fetch(:old, ::Build.num_oldbuilds))
    @logfile.start_section 'start'
    @target.build_proc.call(self, *branch_info)
    success = true
  ensure
    output_status_section(success, $!)
    @logfile.start_section 'end'
    GDB.check_core(@dir)
    careful_link @current_txt, "#{@public}/last.txt" if File.file? @current_txt
    @title = ChkBuild::Title.new(@target, @logfile)
    @title.run_title_hooks
    title = @title.make_title
    Marshal.dump(@title.versions, @parent_pipe)
    @parent_pipe.close
    update_summary(@public, @start_time, title)
    compress_file(@log_filename, "#{@public_log}/#{@start_time}.txt.gz")
    make_diff
    make_html_log(@log_filename, title, "#{@public}/last.html")
    compress_file("#{@public}/last.html", "#{@public}/last.html.gz")
    ::Build.run_upload_hooks(self.suffixed_name)
  end

  def output_status_section(success, err)
    if success
      @logfile.start_section 'success'
    else
      @logfile.start_section 'failure'
      if err
        if CommandError === err
          puts "failed(#{err.reason})"
        else
          puts "failed(#{err.class}:#{err.message})"
          show_backtrace
        end
      else
        puts "failed"
      end
    end
  end

  def work_dir() Pathname.new(@dir) end

  def build_time_sequence
    dirs = Dir.entries(@target_dir)
    dirs.reject! {|d| /\A\d{8}T\d{6}\z/ !~ d } # year 10000 problem
    dirs.sort!
    dirs
  end

  def remove_old_build(current, num)
    dirs = build_time_sequence
    dirs.delete current
    return if dirs.length <= num
    target_dir = @target_dir
    dirs[-num..-1] = []
    dirs.each {|d|
      FileUtils.rmtree "#{target_dir}/#{d}"
    }
  end

  def careful_link(old, new)
    tmp = nil
    i = 0
    loop {
      i += 1
      tmp = "#{new}.tmp#{i}"
      break unless File.exist? tmp
    }
    File.link old, tmp
    File.rename tmp, new
  end

  def careful_make_file(filename, content)
    tmp = nil
    i = 0
    begin
      tmp = "#{filename}.tmp#{i}"
      f = File.open(tmp, File::WRONLY|File::CREAT|File::TRUNC|File::EXCL)
    rescue Errno::EEXIST
      i += 1
      retry
    end
    f << content
    f.close
    File.rename tmp, filename
  end

  def update_title(key, val=nil, &block)
    @title.update_title(key, val, &block)
  end

  def all_log
    File.read(@log_filename)
  end

  def update_summary(public, start_time, title)
    open("#{public}/summary.txt", "a") {|f| f.puts "#{start_time} #{title}" }
    open("#{public}/summary.html", "a") {|f|
      if f.stat.size == 0
        f.puts "<title>#{h self.depsuffixed_name} build summary</title>"
        f.puts "<h1>#{h self.depsuffixed_name} build summary</h1>"
        f.puts "<p><a href=\"../\">chkbuild</a></p>"
      end
      f.print "<a href=\"log/#{start_time}.txt.gz\" name=\"#{start_time}\">#{h start_time}</a> #{h title}"
      f.print " (<a href=\"log/#{start_time}.diff.txt.gz\">diff</a>)" # xxx: diff file may not exist.
      f.puts "<br>"
    }
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

  HTMLTemplate = <<'End'
<html>
  <head>
    <title><%= h title %></title>
    <meta name="author" content="chkbuild">
    <meta name="generator" content="chkbuild">
  </head>
  <body>
    <h1><%= h title %></h1>
    <p><a href="../">chkbuild</a> <a href="summary.html">summary</a></p>
    <pre><%= markup log %></pre>
    <hr>
    <p><a href="../">chkbuild</a> <a href="summary.html">summary</a></p>
  </body>
</html>
End

  def make_html_log(log_filename, title, dst)
    log = File.read(log_filename)
    content = ERB.new(HTMLTemplate).result(binding)
    careful_make_file(dst, content)
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

  def make_diff_content(time)
    tmp = Tempfile.open("#{time}.")
    pat = /#{time}/
    Zlib::GzipReader.wrap(open("#{@public_log}/#{time}.txt.gz")) {|z|
      z.each_line {|line|
        tmp << line.gsub(time, '<buildtime>')
      }
    }
    tmp.flush
    tmp
  end

  def make_diff
    time2 = @start_time
    entries = Dir.entries(@public_log)
    time_seq = []
    entries.each {|f|
      if /\A(\d{8}T\d{6})\.txt\.gz\z/ =~ f # year 10000 problem
        time_seq << $1
      end
    }
    time_seq.sort!
    time_seq.delete time2
    return if time_seq.empty?
    time1 = time_seq.last
    tmp1 = make_diff_content(time1)
    tmp2 = make_diff_content(time2)
    Zlib::GzipWriter.wrap(open("#{@public_log}/#{time2}.diff.txt.gz", "w")) {|z|
      z.puts "--- #{time1}"
      z.puts "+++ #{time2}"
      UDiff.diff(tmp1.path, tmp2.path, z)
    }
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
    opts = {}
    opts = args.pop if Hash === args.last

    if opts.include?(:section)
      secname = opts[:section]
    else
      secname = opts[:reason] || File.basename(command)
    end
    Thread.current[:logfile].start_section(secname) if secname

    puts "+ #{[command, *args].map {|s| Escape.shell_escape s }.join(' ')}"
    pos = STDOUT.pos
    TimeoutCommand.timeout_command(opts.fetch(:timeout, '1h')) {
      opts.each {|k, v|
        next if /\AENV:/ !~ k.to_s
        ENV[$'] = v
      }
      if Process.respond_to? :setrlimit
        resource_unlimit(:RLIMIT_CORE)
	limit = ::Build::DefaultLimit.dup
	opts.each {|k, v| limit[$'.intern] = v if /\Arlimit_/ =~ k.to_s }
        resource_limit(:RLIMIT_CPU, limit.fetch(:cpu))
        resource_limit(:RLIMIT_STACK, limit.fetch(:stack))
        resource_limit(:RLIMIT_DATA, limit.fetch(:data))
        resource_limit(:RLIMIT_AS, limit.fetch(:as))
	#system('sh', '-c', "ulimit -a")
      end
      alt_commands = opts.fetch(:alt_commands, [])
      begin
        exec command, *args
      rescue Errno::ENOENT
        if !alt_commands.empty?
          command = alt_commands.shift
          retry
        else
          raise
        end
      end
    }
    begin
      if $?.exitstatus != 0
        if $?.exited?
          puts "exit #{$?.exitstatus}"
        elsif $?.signaled?
          puts "signal #{SignalNum2Name[$?.termsig]} (#{$?.termsig})"
        elsif $?.stopped?
          puts "stop #{SignalNum2Name[$?.stopsig]} (#{$?.stopsig})"
        else
          p $?
        end
        raise CommandError.new($?, opts.fetch(:section, command))
      end
    ensure
      if block && secname
        add_title_hook(secname, &block)
      end
    end
  end

  SignalNum2Name = Signal.list.invert
  SignalNum2Name.default = 'unknown signal'
end
