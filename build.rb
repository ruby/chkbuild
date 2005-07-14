require 'fileutils'
require 'time'
require 'socket'
require 'zlib'
require "erb"
include ERB::Util

require 'escape'
require 'timeoutcom'
require 'dynamic'
require 'gdb'
require 'ssh'

def tp(obj)
  open("/dev/tty", "w") {|f| f.puts obj.inspect }
end

module Build
  module_function

  def build_dir
    "#{TOP_DIRECTORY}/tmp/build"
  end

  def public_dir
    "#{TOP_DIRECTORY}/tmp/public_html"
  end

  def mkcd(dir)
    FileUtils.mkpath dir
    Dir.chdir dir
  end

  def build_time_sequence
    dirs = Dir.entries(Dynamic.ref(:target_dir))
    dirs.reject! {|d| /\A\d{8}T\d{6}/ !~ d } # year 10000 problem
    dirs.sort!
    dirs
  end

  def remove_old_build(current, num)
    dirs = build_time_sequence
    dirs.delete current
    return if dirs.length <= num
    target_dir = Dynamic.ref(:target_dir)
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

  def update_title(key, val)
    h = Dynamic.ref(:title)
    h[key] = val
  end

  def all_log
    File.read(Dynamic.ref(:log_filename))
  end

  def count_warns
    num_warns = all_log.scan(/warn/i).length
    Dynamic.ref(:title)[:warn] = "#{num_warns}W" if 0 < num_warns
  end

  def make_title
    if !Dynamic.ref(:title)[:status]
      if $!
        if CommandError === $!
          Build.update_title(:status, "failed(#{$!.reason})")
        else
          Build.update_title(:status, "failed(#{$!.class}:#{$!.message})")
        end
      else
        Build.update_title(:status, "failed")
      end
    end
    title_hash = Dynamic.ref(:title)
    Dynamic.ref(:title_order).map {|key| title_hash[key] }.join(' ').gsub(/\s+/, ' ').strip
  end

  def add_finish_hook(&block)
    Dynamic.ref(:finish_hook) << block
  end

  def update_summary(name, public, start_time, title)
    open("#{public}/summary.txt", "a") {|f| f.puts "#{start_time} #{title}" }
    open("#{public}/summary.html", "a") {|f|
      if f.stat.size == 0
        f.puts "<title>#{h name} build summary</title>"
        f.puts "<h1>#{h name} build summary</h1>"
        f.puts "<p><a href=\"../\">autobuild</a></p>"
      end
      f.puts "<a href=\"log/#{start_time}.txt.gz\">#{h start_time}</a> #{h title}<br>"
    }
  end

  def compress_file(src, dst)
    Zlib::GzipWriter.wrap(open(dst, "w")) {|g| g << File.read(src) }
  end

  def build_target(opts, start_time_obj, name, *args)
    Dynamic.bind(
      :start_time => (start_time = start_time_obj.strftime("%Y%m%dT%H%M%S")),
      :target_dir => (target_dir = "#{Build.build_dir}/#{name}"),
      :dir => (dir = "#{target_dir}/#{start_time}"),
      :public => (public = "#{Build.public_dir}/#{name}"),
      :public_log => (public_log = "#{public}/log"),
      :latest_new => (latest_new = "#{public}/latest.new"),
      :log_filename => (log_filename = "#{dir}/log"))
    Build.mkcd target_dir
    raise "already exist: #{dir}" if File.exist? start_time
    Dir.mkdir start_time # fail if it is already exists.
    Dir.chdir start_time
    STDOUT.reopen(log_filename, "w")
    STDERR.reopen(STDOUT)
    STDOUT.sync = true
    STDERR.sync = true
    Build.add_finish_hook { GDB.check_core(dir) }
    puts start_time_obj.iso8601
    system("uname -a")
    remove_old_build(start_time, opts.fetch(:old, 3))
    FileUtils.mkpath(public)
    FileUtils.mkpath(public_log)
    careful_link "log", latest_new
    yield dir, *args
    Dynamic.ref(:title)[:status] ||= 'success'
  ensure
    Dynamic.ref(:finish_hook).reverse_each {|block|
      begin
        block.call
      rescue Exception
      end
    }
    puts Time.now.iso8601
    careful_link latest_new, "#{public}/latest.txt" if File.file? latest_new
    title = make_title
    update_summary(name, public, start_time, title)
    compress_file(log_filename, "#{public_log}/#{start_time}.txt.gz")
  end

  def build_wrapper(opts, start_time_obj, name, *args, &block)
    LOCK.puts name
    Dynamic.bind(:title => {},
                 :title_order => nil,
                 :finish_hook => []) {
      Dynamic.ref(:title)[:version] = name
      Dynamic.ref(:title)[:hostname] = "(#{Socket.gethostname})"
      Dynamic.assign(:title_order, [:status, :warn, :mark, :version, :hostname])
      Build.add_finish_hook { count_warns }
      begin
        Build.build_target(opts, start_time_obj, name, *args, &block)
      rescue CommandError
      end
    }
  end

  def target(target_name, *args, &block)
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
        dep_dirs = []
        dependencies.each {|dep_target_name, dep_branch_name, dep_dir|
          name << "_#{dep_target_name}"
          name << "-#{dep_branch_name}" if dep_branch_name
          dep_dirs << dep_dir
        }
        start_time_obj = Time.now
        dir = "#{Build.build_dir}/#{name}/#{start_time_obj.strftime("%Y%m%dT%H%M%S")}"
        pid = fork {
          Build.build_wrapper(opts, start_time_obj, name, *(branch_info + dep_dirs), &block)
        }
        Process.wait(pid)
        status = $?
        succeed.add [target_name, branch_name, dir] if status.to_i == 0
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
  def run(command, *args)
    opts = {}
    opts = args.pop if Hash === args.last
    puts "+ #{[command, *args].map {|s| Escape.shell_escape s }.join(' ')}"
    pos = STDOUT.pos
    TimeoutCommand.timeout_command(opts.fetch(:timeout, '1h')) {
      opts.each {|k, v|
        next if /\AENV:/ !~ k.to_s
        ENV[$'] = v
      }
      exec command, *args
    }
    begin
      if $?.exitstatus != 0
        if $?.exited?
          puts "exit #{$?.exitstatus}"
        elsif $?.signaled?
          puts "signal #{$?.termsig}"
        elsif $?.stopped?
          puts "stop #{$?.stopsig}"
        else
          p $?
        end
        raise CommandError.new($?, opts.fetch(:reason, command))
      end
    ensure
      if block_given?
        yield File.read(Dynamic.ref(:log_filename), nil, pos)
      end
    end
  end

  def identical_file?(f1, f2)
    s1 = File.stat(f1)
    s2 = File.stat(f2)
    s1.dev == s2.dev && s1.ino == s2.ino
  end

  def cvs_revisions
    h = {}
    Dir.glob("**/CVS").each {|cvs_dir|
      cvsroot = IO.read("#{cvs_dir}/Root").chomp
      repository = IO.read("#{cvs_dir}/Repository").chomp
      ds = cvs_dir.split(%r{/})[0...-1]
      IO.foreach("#{cvs_dir}/Entries") {|line|
        h[[ds, $1]] = [cvsroot, repository, $2] if %r{^/([^/]+)/([^/]*)/} =~ line
      }
    }
    h
  end

  def cvs_print_revisions(h1, h2, viewcvs=nil)
    if !h1
      h2.keys.sort.each {|k|
        f = k.flatten.join('/')
        puts "#{f}\t#{h2[k]}"
      }
    else
      (h1.keys | h2.keys).sort.each {|k|
        f = k.flatten.join('/')
        cvsroot1, repository1, r1 = h1[k] || [nil, nil, 'none']
        cvsroot2, repository2, r2 = h2[k] || [nil, nil, 'none']
        if r1 == r2
          puts "#{f}\t#{r1}"
        else
          line = "#{f}\t#{r1} -> #{r2}"
          if viewcvs
            repository = repository1 || repository2
            url = viewcvs.dup
            url << "/" << repository if repository != '.'
            url << "/#{k[1]}?r1=#{r1};r2=#{r2}"
            line << "\t" << url
          end
          puts line
        end
      }
    end
  end

  def cvs(working_dir, cvsroot, mod, branch, opts={})
    if File.directory?(working_dir)
      Dir.chdir(working_dir) {
        h1 = cvs_revisions
        Build.run("cvs", "-f", "-z3", "-Q", "update", "-dP", opts)
        h2 = cvs_revisions
        cvs_print_revisions(h1, h2, opts[:viewcvs]||opts[:cvsweb])
      }
    else
      h1 = nil
      if identical_file?(Dynamic.ref(:dir), '.') &&
         !(ts = build_time_sequence - [Dynamic.ref(:start_time)]).empty? &&
         File.directory?(old_working_dir = "#{Dynamic.ref(:target_dir)}/#{ts.last}/#{working_dir}")
        Dir.chdir(old_working_dir) {
          h1 = cvs_revisions
        }
      end
      if branch
        Build.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-d", working_dir, "-Pr", branch, mod, opts)
      else
        Build.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-d", working_dir, "-P", mod, opts)
      end
      Dir.chdir(working_dir) {
        h2 = cvs_revisions
        cvs_print_revisions(h1, h2, opts[:viewcvs]||opts[:cvsweb])
      }
    end
  end

  def make(*targets)
    if targets.empty?
      Build.run("make")
    else
      targets.each {|target|
        Build.run("make", target, :reason => target)
      }
    end
  end

  def ssh_known_host(arg)
    SSH.add_known_host(arg)
  end

  TOP_DIRECTORY = Dir.getwd

  FileUtils.mkpath Build.build_dir
  LOCK = open("#{Build.build_dir}/.lock", "w")
  if LOCK.flock(File::LOCK_EX|File::LOCK_NB) == false
    raise "another chkbuild is running."
  end
  LOCK.sync = true
end

STDOUT.sync = true
