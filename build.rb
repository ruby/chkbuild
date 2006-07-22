require 'fileutils'
require 'time'
require 'socket'
require 'zlib'
require "erb"
include ERB::Util
require "uri"
require "tempfile"

require 'escape'
require 'timeoutcom'
require 'gdb'
require "udiff"
require "logfile"
require "util"

begin
  Process.setpriority(Process::PRIO_PROCESS, 0, 10)
rescue Errno::EACCES # already niced to 11 or more
end

File.umask(002)
STDIN.reopen("/dev/null", "r")

class Build
  def Build.target(target_name, *args, &block)
    b = Build.new
    $Build = b
    result = b.start(target_name, *args, &block)
    $Build = nil
    result
  end

  def self.build_dir() "#{TOP_DIRECTORY}/tmp/build" end
  def self.public_dir() "#{TOP_DIRECTORY}/tmp/public_html" end

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

  def Build.update_title(*args, &b) $Build.update_title(*args, &b) end
  def update_title(key, val=nil)
    if val == nil && block_given?
      val = yield @title[key]
      return if !val
    end
    @title[key] = val
    unless @title_order.include? key
      @title_order[-1,0] = [key]
    end
  end

  def Build.all_log(*args, &b) $Build.all_log(*args, &b) end
  def all_log
    File.read(@log_filename)
  end

  def count_warns
    num_warns = all_log.scan(/warn/i).length
    @title[:warn] = "#{num_warns}W" if 0 < num_warns
  end

  def make_title(err=$!)
    if !@title[:status]
      if err
        if CommandError === err
          update_title(:status, "failed(#{err.reason})")
        else
          show_backtrace
          update_title(:status, "failed(#{err.class}:#{err.message})")
        end
      else
        update_title(:status, "failed")
      end
    end
    title_hash = @title
    @title_order.map {|key| title_hash[key] }.flatten.join(' ').gsub(/\s+/, ' ').strip
  end

  def Build.add_finish_hook(*args, &b) $Build.add_finish_hook(*args, &b) end
  def add_finish_hook(&block)
    @finish_hook << block
  end

  def update_summary(name, public, start_time, title)
    open("#{public}/summary.txt", "a") {|f| f.puts "#{start_time} #{title}" }
    open("#{public}/summary.html", "a") {|f|
      if f.stat.size == 0
        f.puts "<title>#{h name} build summary</title>"
        f.puts "<h1>#{h name} build summary</h1>"
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

  class << Build
    attr_accessor :num_oldbuilds
  end
  Build.num_oldbuilds = 3

  def build_target(opts, start_time_obj, name, *args)
    @start_time = start_time_obj.strftime("%Y%m%dT%H%M%S")
    @target_dir = "#{Build.build_dir}/#{name}"
    @dir = "#{@target_dir}/#{@start_time}"
    @public = "#{Build.public_dir}/#{name}"
    @public_log = "#{@public}/log"
    @current_txt = "#{@public}/current.txt"
    @log_filename = "#{@dir}/log"
    mkcd @target_dir
    raise "already exist: #{@start_time}" if File.exist? @start_time
    Dir.mkdir @start_time # fail if it is already exists.
    Dir.chdir @start_time

    @logfile = LogFile.new(@log_filename)
    Thread.current[:logfile] = @logfile
    @logfile.change_default_output

    add_finish_hook { GDB.check_core(@dir) }
    @logfile.start_section name
    puts "args: #{args.inspect}"
    system("uname -a")
    FileUtils.mkpath(@public)
    FileUtils.mkpath(@public_log)
    careful_link "log", @current_txt
    remove_old_build(@start_time, opts.fetch(:old, Build.num_oldbuilds))
    @logfile.start_section 'start'
    yield @dir, *args
    @logfile.start_section 'success'
    @title[:status] ||= 'success'
  ensure
    @finish_hook.reverse_each {|block|
      begin
        block.call
      rescue Exception
        p $!
      end
    }
    @logfile.start_section 'end'
    careful_link @current_txt, "#{@public}/last.txt" if File.file? @current_txt
    title = make_title
    Marshal.dump([@title, @title_order], @parent_pipe)
    @parent_pipe.close
    update_summary(name, @public, @start_time, title)
    compress_file(@log_filename, "#{@public_log}/#{@start_time}.txt.gz")
    make_diff
    make_html_log(@log_filename, title, "#{@public}/last.html")
    compress_file("#{@public}/last.html", "#{@public}/last.html.gz")
    Build.run_upload_hooks
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

  def build_wrapper(parent_pipe, opts, start_time_obj, simple_name, name, dep_versions, *args, &block)
    LOCK.puts name
    @parent_pipe = parent_pipe
    @title = {}
    @finish_hook = []
    @title[:version] = simple_name
    @title[:dep_versions] = dep_versions
    @title[:hostname] = "(#{Socket.gethostname})"
    @title_order = [:status, :warn, :mark, :version, :dep_versions, :hostname]
    add_finish_hook { count_warns }
    success = false
    begin
      build_target(opts, start_time_obj, name, *args, &block)
      success = true
    rescue CommandError
    end
    success
  end

  def start(target_name, *args, &block)
    opts = {}
    opts = args.pop if Hash === args.last
    branches = []
    dep_targets = []
    args.each {|arg|
      if Depend === arg
        dep_targets << arg
      else
        branches << arg
      end
    }
    if branches.empty?
      branches << []
    end
    succeed = Depend.new
    branches.each {|branch_info|
      branch_name = branch_info[0]
      Depend.perm(dep_targets) {|dependencies|
        name = target_name.dup
        name << "-#{branch_name}" if branch_name
        simple_name = name.dup
        dep_dirs = []
        dep_versions = []
        dependencies.each {|dep_target_name, dep_branch_name, dep_dir, dep_ver|
          name << "_#{dep_target_name}"
          name << "-#{dep_branch_name}" if dep_branch_name
          dep_dirs << dep_dir
          dep_versions.concat dep_ver
        }
        start_time_obj = Time.now
        dir = "#{Build.build_dir}/#{name}/#{start_time_obj.strftime("%Y%m%dT%H%M%S")}"
        r, w = IO.pipe
        r.close_on_exec = true
        w.close_on_exec = true
        pid = fork {
          r.close
          if build_wrapper(w, opts, start_time_obj, simple_name, name, dep_versions, *(branch_info + dep_dirs), &block)
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
          title, title_order = Marshal.load(str)
          version = title[:version]
          version_list = ["(#{version})", *title[:dep_versions]]
        rescue ArgumentError
          version_list = []
        end
	if status.to_i == 0
	  succeed.add [target_name, branch_name, dir, version_list] if status.to_i == 0
	end
      }
    }
    succeed
  end

  class Depend
    def initialize
      @list = []
    end

    def add(elt)
      @list << elt
    end

    def each
      @list.each {|elt| yield elt }
    end

    def Depend.perm(depend_list, prefix=[], &block)
      if depend_list.empty?
        yield prefix
      else
        first, *rest = depend_list
        first.each {|elt|
          Depend.perm(rest, prefix + [elt], &block)
        }
      end
    end
  end

  class CommandError < StandardError
    def initialize(status, reason, message=reason)
      super message
      @reason = reason
      @status = status
    end

    attr_accessor :reason
  end
  def Build.run(*args, &b) $Build.run(*args, &b) end
  def run(command, *args)
    opts = {}
    opts = args.pop if Hash === args.last

    if opts.include?(:section)
      Thread.current[:logfile].start_section(opts[:section]) if opts[:section]
    else
      Thread.current[:logfile].start_section(opts[:reason] || File.basename(command))
    end

    puts "+ #{[command, *args].map {|s| Escape.shell_escape s }.join(' ')}"
    pos = STDOUT.pos
    TimeoutCommand.timeout_command(opts.fetch(:timeout, '1h')) {
      opts.each {|k, v|
        next if /\AENV:/ !~ k.to_s
        ENV[$'] = v
      }
      if Process.respond_to? :setrlimit
        resource_unlimit(:RLIMIT_CORE)
	limit = DefaultLimit.dup
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
        raise CommandError.new($?, opts.fetch(:reason, command))
      end
    ensure
      if block_given?
        log = File.read(@log_filename, nil, pos)
        log_filename = @log_filename
        class << log; self end.funcall(:define_method, :modify_log) {|str|
          STDOUT.seek(pos)
          File.truncate(log_filename, pos)
          STDOUT.print str
        }
        yield log
      end
    end
  end

  SignalNum2Name = Signal.list.invert
  SignalNum2Name.default = 'unknown signal'

  DefaultLimit = {
    :cpu => 3600 * 4,
    :stack => 1024 * 1024 * 40,
    :data => 1024 * 1024 * 100,
    :as => 1024 * 1024 * 100
  }

  def self.limit(hash)
    DefaultLimit.update(hash)
  end

  @upload_hook = []
  def self.add_upload_hook(&block)
    @upload_hook << block
  end
  def self.run_upload_hooks
    @upload_hook.reverse_each {|block|
      begin
        block.call name
      rescue Exception
        p $!
      end
    }
  end

  TOP_DIRECTORY = Dir.getwd

  FileUtils.mkpath Build.build_dir
  lock_path = "#{Build.build_dir}/.lock"
  LOCK = open(lock_path, File::WRONLY|File::CREAT)
  if LOCK.flock(File::LOCK_EX|File::LOCK_NB) == false
    raise "another chkbuild is running."
  end
  LOCK.truncate(0)
  LOCK.sync = true
  LOCK.close_on_exec = true
  lock_pid = $$
  at_exit {
    File.unlink lock_path if $$ == lock_pid
  }
end

STDOUT.sync = true
