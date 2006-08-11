require 'chkbuild'

require "util"
require 'chkbuild/target'
require 'chkbuild/build'

begin
  Process.setpriority(Process::PRIO_PROCESS, 0, 10)
rescue Errno::EACCES # already niced to 11 or more
end

File.umask(002)
STDIN.reopen("/dev/null", "r")
STDOUT.sync = true

class Build
  def Build.main() ChkBuild.main end
  def Build.def_target(target_name, *args, &block)
    ChkBuild.def_target(target_name, *args, &block)
  end

  def self.limit(hash)
    ChkBuild.limit(hash)
  end

  @upload_hook = []
  def self.add_upload_hook(&block)
    @upload_hook << block
  end
  def self.run_upload_hooks(suffixed_name)
    @upload_hook.reverse_each {|block|
      begin
        block.call suffixed_name
      rescue Exception
        p $!
      end
    }
  end

  TOP_DIRECTORY = Dir.getwd

  ChkBuild.build_top.mkpath
  LOCK_PATH = ChkBuild.build_top + '.lock'

  def Build.lock_start
    if !defined?(@lock_io)
      @lock_io = LOCK_PATH.open(File::WRONLY|File::CREAT)
    end
    if @lock_io.flock(File::LOCK_EX|File::LOCK_NB) == false
      raise "another chkbuild is running."
    end
    @lock_io.truncate(0)
    @lock_io.sync = true
    @lock_io.close_on_exec = true
    @lock_io.puts "locked pid:#{$$}"
    lock_pid = $$
    at_exit {
      @lock_io.puts "exit pid:#{$$}" if $$ == lock_pid
    }
  end

  def Build.lock_puts(mesg)
    @lock_io.puts mesg
  end
end
