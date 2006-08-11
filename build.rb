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
end
