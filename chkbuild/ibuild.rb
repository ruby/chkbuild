# chkbuild/ibuild.rb - ibuild object implementation.
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

class ChkBuild::IBuild # internal build
  include Util

  def initialize(start_time_obj, start_time, target, suffixes, suffixed_name, depsuffixed_name, depbuilds, opts)
    @start_time_obj = start_time_obj
    @t = start_time
    @target = target
    @suffixes = suffixes
    @suffixed_name = suffixed_name
    @depsuffixed_name = depsuffixed_name
    @depbuilds = depbuilds
    @target_dir = ChkBuild.build_top + @depsuffixed_name
    logdir_relpath = "#{@depsuffixed_name}/log"
    @public_logdir = ChkBuild.public_top+logdir_relpath
    current_txt_relpath = "#{@depsuffixed_name}/current.txt"
    @current_txt = ChkBuild.public_top+current_txt_relpath
    @opts = opts
  end
  attr_reader :target, :suffixes, :depbuilds
  attr_reader :target_dir, :opts
  attr_reader :suffixed_name, :depsuffixed_name

  def inspect
    "\#<#{self.class}: #{self.depsuffixed_name}>"
  end

  def traverse_depbuild(memo={}, &block)
    return if memo[self]
    memo[self] = true
    yield self
    @depbuilds.each {|depbuild|
      depbuild.traverse_depbuild(memo, &block)
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

  ################

  def internal_build
    if child_build_wrapper(nil)
      exit 0
    else
      exit 1
    end
  end

  def start_time
    return @t
  end

  def child_build_wrapper(parent_pipe)
    @errors = []
    child_build_target
  end

  def make_local_tmpdir
    tmpdir = @build_dir + 'tmp'
    tmpdir.mkdir(0700)
    ENV['TMPDIR'] = tmpdir.to_s
  end

  def child_build_target
    if @opts[:nice]
      begin
        Process.setpriority(Process::PRIO_PROCESS, 0, @opts[:nice])
      rescue Errno::EACCES # already niced.
      end
    end
    setup_build
    @logfile.start_section 'start'
    puts "start-time: #{@t}"
    puts "build-dir: #{@build_dir}"
    show_options
    show_cpu_info
    show_memory_info
    show_process_limits
    show_process_ps
    ret = self.do_build
    @logfile.start_section 'end'
    puts "elapsed #{format_elapsed_time(Time.now - @start_time_obj)}"
    make_compressed_rawlog
    ret
  end

  def setup_build
    @build_dir = ChkBuild.build_top + @t
    @log_filename = @build_dir + 'log'
    mkcd @target_dir
    Dir.chdir @t
    @logfile = ChkBuild::LogFile.write_open(@log_filename, self)
    @logfile.change_default_output
    (ChkBuild.public_top+@depsuffixed_name).mkpath
    @public_logdir.mkpath
    force_link "log", @current_txt
    make_local_tmpdir
    remove_old_build(@t, @opts.fetch(:old, ChkBuild.num_oldbuilds))
    path = ["#{@build_dir}/bin"]
    path.concat @opts[:additional_path] if @opts[:additional_path]
    path.concat ENV['PATH'].split(/:/)
    ENV['PATH'] = path.join(':')
    if @opts[:additional_pkg_config_path]
      pkg_config_path = @opts[:additional_pkg_config_path]
      if ENV['PKG_CONFIG_PATH']
        pkg_config_path += ENV['PKG_CONFIG_PATH'].split(/:/)
      end
      ENV['PKG_CONFIG_PATH'] = pkg_config_path.join(':')
    end
  end

  def make_compressed_rawlog
    compressed_rawlog_relpath = "#{@depsuffixed_name}/log/#{@t}.log.txt.gz"
    Util.compress_file(@log_filename, ChkBuild.public_top+compressed_rawlog_relpath)
  end

  def show_options
    @opts.keys.sort_by {|k| k.to_s }.each {|k|
      v = @opts[k]
      puts "option #{k.inspect} => #{v.inspect}"
    }
  end

  def show_cpu_info
    if File.exist? '/proc/cpuinfo' # GNU/Linux, NetBSD
      self.run('cat', '/proc/cpuinfo', :section => 'cpu-info')
    end
    if /freebsd/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.model', 'hw.ncpu', 'hw.byteorder', 'hw.clockrate', 'hw.machine', 'hw.machine_arch', :section => 'cpu-info')
    end
    if /dragonfly/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.model', 'hw.ncpu', 'hw.byteorder', 'hw.clockrate', 'hw.machine', 'hw.machine_arch', :section => 'cpu-info')
    end
    if /netbsd/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.model', 'hw.ncpu', 'hw.byteorder', 'hw.machine', 'hw.machine_arch', :section => 'cpu-info')
    end
    if /openbsd/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.model', 'hw.ncpu', 'hw.byteorder', 'hw.cpuspeed', 'hw.machine', :section => 'cpu-info')
    end
  end

  def show_memory_info
    if File.exist? '/proc/meminfo' # GNU/Linux, NetBSD
      self.run('cat', '/proc/meminfo', :section => 'memory-info')
    end
    if /freebsd/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.realmem', 'hw.physmem', 'hw.usermem', :section => 'memory-info')
    end
    if /dragonfly/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.physmem', 'hw.usermem', :section => 'memory-info')
    end
    if /netbsd/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.physmem', 'hw.usermem', 'hw.physmem64', 'hw.usermem64', :section => 'memory-info')
    end
    if /openbsd/ =~ RUBY_PLATFORM
      self.run('sysctl', 'hw.physmem', 'hw.usermem', :section => 'memory-info')
    end
  end

  def show_process_limits
    if File.exist?('/bin/pflags') # Solaris
      self.run('pflags', $$.to_s)
    elsif File.exist? '/proc/self/status' # GNU/Linux
      # Don't print /proc/self/status on Solaris because it is a binary file.
      self.run('cat', '/proc/self/status', :section => 'process-status')
    end
    if File.exist? '/proc/self/limits' # GNU/Linux
      self.run('cat', '/proc/self/limits', :section => 'process-limits')
    end
  end

  def show_process_ps
    @logfile.start_section 'process-ps'
    # POSIX
    %w[ruser user nice tty comm].each {|field| show_ps_result($$, field) }
    if /dragonfly/ !~ RUBY_PLATFORM
      # POSIX has rgroup, group and args but
      # DragonFly BSD's ps don't have them.
      %w[rgroup group args].each {|field| show_ps_result($$, field) }
    end
    if /linux/ =~ RUBY_PLATFORM
      %w[
        ruid ruser euid euser suid suser fuid fuser
        rgid rgroup egid egroup sgid sgroup fgid fgroup
        blocked caught ignored pending
        cls sched rtprio f label
      ].each {|field| show_ps_result($$, field) }
    end
  end

  def show_ps_result(pid, field)
    result = `ps -o #{field} -p #{pid} 2>&1`
    return unless $?.success?
    result.sub!(/\A.*\n/, '') # strip the header line
    result.strip!
    puts "ps -o #{field} : #{result}"
  end

  def show_title_info(title, title_version, title_assoc)
    @logfile.start_section 'title-info'
    puts "title-info title:#{Escape._ltsv_val(title)}"
    puts "title-info title_version:#{Escape._ltsv_val(title_version)}"
    title_assoc.each {|k, v|
      puts "title-info #{Escape._ltsv_key k}:#{Escape._ltsv_val v}"
    }
  end

  def do_build
    ret = nil
    with_procmemsize(@opts) {
      ret = catch_error {
        ChkBuild.fetch_build_proc(@target.target_name).call(self)
      }
      output_status_section
    }
    ret
  end

  attr_reader :logfile

  def with_procmemsize(opts)
    if opts[:procmemsize]
      current_pid = $$
      ret = nil
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
    unless ChkBuild::Build::CommandError === err || CommandTimeout === err
      show_backtrace err
    end
    GDB.check_core(@build_dir)
    if ChkBuild::Build::CommandError === err
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
    rescue Exception
      @logfile.start_section("neterror")
      raise
    end
  end

  def build_dir() @build_dir end

  def remove_old_build(current, num)
    dirs = build_time_sequence
    dirs.delete current
    return if dirs.length <= num
    dirs[-num..-1] = []
    dirs.each {|d|
      d = @target_dir+d
      if d.symlink?
        if d.exist?
          d.realpath.rmtree
          d.unlink
        else
          d.unlink
        end
      else
        d.rmtree
      end
    }
  end

  def show_backtrace(err=$!)
    puts "|#{err.message} (#{err.class})"
    err.backtrace.each {|pos| puts "| #{pos}" }
  end

  def run(command, *args, &block)
    opts = @opts.dup
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
    if !opts.include?(:process_remain_timeout)
      opts[:process_remain_timeout] = '1min'
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

    puts "+ #{Escape.shell_command [command, *args]}" if !opts[:hide_commandline]
    ruby_script = script_to_run_in_child(opts, command, alt_commands, *args)
    begin
      command_status = TimeoutCommand.timeout_command(ruby_script, @logfile.filename, opts.fetch(:timeout, '1h'), STDERR, opts)
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
          puts "chkbuild: signal #{SignalNum2Name[command_status.termsig]} (#{command_status.termsig})"
        elsif command_status.stopped?
          puts "stop #{SignalNum2Name[command_status.stopsig]} (#{command_status.stopsig})"
        else
          p command_status
        end
        raise ChkBuild::Build::CommandError.new(command_status, opts.fetch(:section, command))
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
      limit = {}
      opts.each {|k, v|
        limit[$'.intern] = v if /\Ar?limit_/ =~ k.to_s && v
      }
      ruby_script << <<-"End"
        def resource_limit(resource, val)
          if Symbol === resource
            begin
              resource = Process.const_get(resource)
            rescue NameError
              return
            end
          end
          _cur_limit, max_limit = Process.getrlimit(resource)
          case val
          when Integer
            if max_limit < val
              val = max_limit
            end
            Process.setrlimit(resource, val, val)
          when :unlimited
            Process.setrlimit(resource, max_limit, max_limit)
          else
            raise ArgumentError, "unexpected resource value"
          end
        end
      End

      %w[core cpu stack data as].each {|res|
        if limit.has_key?(res.intern)
          v = limit[res.intern]
          if limit[res.intern] == :unlimited
            ruby_script << "v = :unlimited\n"
          else
            ruby_script << "v = #{v.to_i}\n"
          end
          ruby_script << "resource_limit(:RLIMIT_#{res.upcase}, v)\n"
        end
      }
    end

    if opts.include?(:stdout)
      ruby_script << "open(#{opts[:stdout].dump}, 'a') {|f| STDOUT.reopen(f) }\n"
    end
    if opts.include?(:stderr)
      ruby_script << "open(#{opts[:stderr].dump}, 'a') {|f| STDERR.reopen(f) }\n"
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

    make_opts, targets = args.partition {|a| /\A-|=/ =~ a }
    if targets.empty?
      opts[:section] ||= 'make'
      self.run("gmake", *(make_opts + [opts]))
    else
      targets.each {|target|
        h = opts.dup
        h[:reason] = target
        h[:section] ||= target
        self.run("gmake", *(make_opts + [target, h]))
      }
    end
  end

  def cc_version(cc, opts2=nil)
    opts = @opts.dup
    opts.update opts2 if opts2

    secname = opts.has_key?(:section) ? opts[:section] : 'cc-version'

    # gcc (Debian 4.4.5-8) 4.4.5
    if %r{(\A|/)gcc\z} =~ cc
      cmd = "#{cc} --version"
      message = `#{cmd} 2>&1`
      status = $?
      if status.success?
	@logfile.start_section(secname) if secname
        puts "+ #{cmd}"
        puts message
        return
      end
    end

    # IBM XL C/C++ for AIX, V12.1 (5765-J02, 5725-C72)
    # Version: 12.01.0000.0000
    if %r{(\A|/)xlc\z} =~ cc
      cmd = "#{cc} -qversion"
      message = `#{cmd} 2>&1`
      status = $?
      if status.success?
	@logfile.start_section(secname) if secname
        puts "+ #{cmd}"
        puts message
        return
      end
    end

    if %r{(\A|/)cc\z} =~ cc
      # FreeBSD clang version 3.3 (tags/RELEASE_33/final 183502) 20130610
      # Target: x86_64-unknown-freebsd10.0
      # Thread model: posix
      cmd = "#{cc} --version"
      message = `#{cmd} 2>&1`
      status = $?
      if status.success? && /^FreeBSD clang version/ =~ message
	@logfile.start_section(secname) if secname
        puts "+ #{cmd}"
        puts message
        return
      end

      # cc: Sun C 5.10 SunOS_i386 2009/06/03
      # usage: cc [ options] files.  Use 'cc -flags' for details
      cmd = "#{cc} -V"
      message = `#{cmd} 2>&1`
      status = $?
      if status.success? && /^cc: Sun C/ =~ message
	@logfile.start_section(secname) if secname
        puts "+ #{cmd}"
        puts message
        return
      end
    end
  end

  def install_rsync_wrapper(bindir="#{@build_dir}/bin")
    real_rsync = Util.search_command 'rsync'
    return false if !real_rsync
    rsync_repos = ChkBuild.build_top + 'rsync-repos'
    FileUtils.mkpath rsync_repos
    script = <<-"End1".gsub(/^[ \t]*/, '') + <<-'End2'
      #!#{RbConfig.ruby}

      require 'fileutils'

      real_rsync = #{real_rsync.dump}
      rsync_repos = #{rsync_repos.to_s.dump}
    End1
      mirrors = []
      argv2 = []
      ARGV.each_with_index {|arg, i|
        if i == ARGV.length - 1
	  m = nil
	elsif %r{/\z} !~ arg
	  m = nil
        elsif /::/ =~ arg
	  m = rsync_repos + '/' + arg.sub(/::/, '/')
	elsif %r{\Arsync://} =~ arg
	  m = $'
	  m = nil if /%/ =~ m # URL escape
	else
	  m = nil
	end
	if m && %r{(?:\A|/)\.\.(?:/|\z)} =~ m
	  m = nil
	end
	if m
	  mirrors << [arg, m.chomp('/')]
	  argv2.push m
	else
	  argv2.push arg
	end
      }

      mirrors.each {|src, m|
        FileUtils.mkpath m
        mirror_command = [real_rsync, '-Lrtvzp', '--delete', src, m]
	STDERR.puts mirror_command.join(' ')
	system *mirror_command
      }

      command = [real_rsync, *argv2]
      STDERR.puts command.join(' ')
      system *command
    End2
    FileUtils.mkpath bindir
    open("#{bindir}/rsync", 'w', 0755) {|f|
      f.print script
    }
    true
  end
end
