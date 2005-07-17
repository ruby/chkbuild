require 'fileutils'
require 'time'
require 'socket'
require 'zlib'
require "erb"
include ERB::Util
require "uri"
require "etc"

require 'escape'
require 'timeoutcom'
require 'gdb'
require 'ssh'

begin
  Process.setpriority(Process::PRIO_PROCESS, 0, 10)
rescue Errno::EACCES # already niced to 11 or more
end

File.umask(002)
STDIN.reopen("/dev/null", "r")

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
    dirs = Dir.entries(@target_dir)
    dirs.reject! {|d| /\A\d{8}T\d{6}/ !~ d } # year 10000 problem
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

  def update_title(key, val)
    h = @title
    h[key] = val
  end

  def all_log
    File.read(@log_filename)
  end

  def count_warns
    num_warns = all_log.scan(/warn/i).length
    @title[:warn] = "#{num_warns}W" if 0 < num_warns
  end

  def make_title
    if !@title[:status]
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
    title_hash = @title
    @title_order.map {|key| title_hash[key] }.join(' ').gsub(/\s+/, ' ').strip
  end

  def add_finish_hook(&block)
    @finish_hook << block
  end

  def add_upload_hook(&block)
    @upload_hook << block
  end

  def update_summary(name, public, start_time, title)
    open("#{public}/summary.txt", "a") {|f| f.puts "#{start_time} #{title}" }
    open("#{public}/summary.html", "a") {|f|
      if f.stat.size == 0
        f.puts "<title>#{h name} build summary</title>"
        f.puts "<h1>#{h name} build summary</h1>"
        f.puts "<p><a href=\"../\">chkbuild</a></p>"
      end
      f.puts "<a href=\"log/#{start_time}.txt.gz\">#{h start_time}</a> #{h title}<br>"
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
    <p><a href="../">chkbuild</a></p>
    <pre><%= markup log %></pre>
    <hr>
    <p><a href="../">chkbuild</a></p>
  </body>
</html>
End

  def make_html_log(log_filename, title, dst)
    log = File.read(log_filename)
    content = ERB.new(HTMLTemplate).result(binding)
    careful_make_file(dst, content)
  end

  def compress_file(src, dst)
    Zlib::GzipWriter.wrap(open(dst, "w")) {|g| g << File.read(src) }
  end

  def build_target(opts, start_time_obj, name, *args)
    @start_time = start_time_obj.strftime("%Y%m%dT%H%M%S")
    @target_dir = "#{Build.build_dir}/#{name}"
    @dir = "#{@target_dir}/#{@start_time}"
    @public = "#{Build.public_dir}/#{name}"
    @public_log = "#{@public}/log"
    @current_txt = "#{@public}/current.txt"
    @log_filename = "#{@dir}/log"
    Build.mkcd @target_dir
    raise "already exist: #{dir}" if File.exist? @start_time
    Dir.mkdir @start_time # fail if it is already exists.
    Dir.chdir @start_time
    STDOUT.reopen(@log_filename, "w")
    STDERR.reopen(STDOUT)
    STDOUT.sync = true
    STDERR.sync = true
    Build.add_finish_hook { GDB.check_core(@dir) }
    puts start_time_obj.iso8601
    puts "args: #{args.inspect}"
    system("uname -a")
    FileUtils.mkpath(@public)
    FileUtils.mkpath(@public_log)
    careful_link "log", @current_txt
    remove_old_build(@start_time, opts.fetch(:old, 3))
    yield @dir, *args
    @title[:status] ||= 'success'
  ensure
    @finish_hook.reverse_each {|block|
      begin
        block.call
      rescue Exception
      end
    }
    puts Time.now.iso8601
    careful_link @current_txt, "#{@public}/last.txt" if File.file? @current_txt
    title = make_title
    update_summary(name, @public, @start_time, title)
    compress_file(@log_filename, "#{@public_log}/#{@start_time}.txt.gz")
    make_html_log(@log_filename, title, "#{@public}/last.html")
    compress_file("#{@public}/last.html", "#{@public}/last.html.gz")
    @upload_hook.reverse_each {|block|
      begin
        block.call name
      rescue Exception
      end
    }
  end

  @upload_hook ||= []
  def build_wrapper(opts, start_time_obj, name, *args, &block)
    LOCK.puts name
    @title = {}
    @finish_hook = []
    @upload_hook ||= []
    @title[:version] = name
    @title[:hostname] = "(#{Socket.gethostname})"
    @title_order = [:status, :warn, :mark, :version, :hostname]
    add_finish_hook { count_warns }
    begin
      Build.build_target(opts, start_time_obj, name, *args, &block)
    rescue CommandError
    end
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
      if Process.respond_to? :setrlimit
        resource_unlimit(:RLIMIT_CORE)
        resource_limit(:RLIMIT_CPU, opts.fetch(:rlimit_cpu, 3600 * 4))
        resource_limit(:RLIMIT_DATA, opts.fetch(:rlimit_data, 1024 * 1024 * 500))
        resource_limit(:RLIMIT_STACK, opts.fetch(:rlimit_stack, 1024 * 1024 * 40))
        resource_limit(:RLIMIT_AS, opts.fetch(:rlimit_as, 1024 * 1024 * 500))
      end
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
        yield File.read(@log_filename, nil, pos)
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
    if h1
      changes = 'changes:'
      (h1.keys | h2.keys).sort.each {|k|
        f = k.flatten.join('/')
        cvsroot1, repository1, r1 = h1[k] || [nil, nil, 'none']
        cvsroot2, repository2, r2 = h2[k] || [nil, nil, 'none']
        if r1 != r2
          if changes
            puts changes
            changes = nil
          end
          line = "#{f}\t#{r1} -> #{r2}"
          if viewcvs
            repository = repository1 || repository2
            uri = URI.parse(viewcvs)
            path = uri.path.dup
            path << "/" << repository if repository != '.'
            path << "/#{k[1]}"
            uri.path = path
            query = (uri.query || '').split(/[;&]/)
            if r1 == 'none'
              query << "rev=#{r2}"
            elsif r2 == 'none'
              query << "rev=#{r1}"
            else
              query << "r1=#{r1}" << "r2=#{r2}"
            end
            uri.query = query.join(';')
            line << "\t" << uri.to_s
          end
          puts line
        end
      }
    end
    puts 'revisions:'
    h2.keys.sort.each {|k|
      f = k.flatten.join('/')
      cvsroot2, repository2, r2 = h2[k] || [nil, nil, 'none']
      puts "#{f}\t#{r2}"
    }
  end

  def cvs(cvsroot, mod, branch, opts={})
    opts = opts.dup
    working_dir = opts.fetch(:working_dir, mod)
    if !File.exist? "#{ENV['HOME']}/.cvspass"
      opts['ENV:CVS_PASSFILE'] = '/dev/null' # avoid warning
    end
    if File.directory?(working_dir)
      Dir.chdir(working_dir) {
        h1 = cvs_revisions
        Build.run("cvs", "-f", "-z3", "-Q", "update", "-dP", opts)
        h2 = cvs_revisions
        cvs_print_revisions(h1, h2, opts[:viewcvs]||opts[:cvsweb])
      }
    else
      h1 = nil
      if identical_file?(@dir, '.') &&
         !(ts = build_time_sequence - [@start_time]).empty? &&
         File.directory?(old_working_dir = "#{@target_dir}/#{ts.last}/#{working_dir}")
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

  def gnu_savannah_cvs(proj, mod, branch, opts={})
    Build.ssh_known_host("savannah.gnu.org ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAIEAzFQovi+67xa+wymRz9u3plx0ntQnELBoNU4SCl3RkwSFZkrZsRTC0fTpOKatQNs1r/BLFoVt21oVFwIXVevGQwB+Lf0Z+5w9qwVAQNu/YUAFHBPTqBze4wYK/gSWqQOLoj7rOhZk0xtAS6USqcfKdzMdRWgeuZ550P6gSzEHfv0=")
    opts = opts.dup
    opts["ENV:CVS_RSH"] ||= "ssh"
    opts[:viewcvs] ||= "http://savannah.gnu.org/cgi-bin/viewcvs/#{proj}?diff_format=u"
    Build.cvs(":ext:anoncvs@savannah.gnu.org:/cvsroot/#{proj}", mod, branch, opts)
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

  def rsync_ssh_upload_target(rsync_target, private_key=nil)
    Build.add_upload_hook {|name|
      Build.do_upload_rsync_ssh(rsync_target, private_key, name)
    }
  end

  def do_upload_rsync_ssh(rsync_target, private_key, name)
    if %r{\A(?:([^@:]+)@)([^:]+)::(.*)\z} !~ rsync_target
      raise "invalid rsync target: #{rsync_target.inspect}"
    end
    remote_user = $1 || ENV['USER'] || Etc.getpwuid.name
    remote_host = $2
    remote_path = $3
    local_host = Socket.gethostname
    private_key ||= "#{ENV['HOME']}/.ssh/chkbuild-#{local_host}-#{remote_host}"

    pid = fork {
      ENV.delete 'SSH_AUTH_SOCK'
      exec "rsync", "--delete", "-rte", "ssh -akxi #{private_key}", "#{Build.public_dir}/#{name}", "#{rsync_target}"
    }
    Process.wait pid
  end

  TOP_DIRECTORY = Dir.getwd

  FileUtils.mkpath Build.build_dir
  lock_path = "#{Build.build_dir}/.lock"
  LOCK = open(lock_path, "w")
  if LOCK.flock(File::LOCK_EX|File::LOCK_NB) == false
    raise "another chkbuild is running."
  end
  LOCK.sync = true
  lock_pid = $$
  at_exit {
    File.unlink lock_path if $$ == lock_pid
  }
end

STDOUT.sync = true
