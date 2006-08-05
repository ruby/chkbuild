require 'fileutils'

module ChkBuild
end
require "util"
require 'chkbuild/target'
require 'chkbuild/build'

begin
  Process.setpriority(Process::PRIO_PROCESS, 0, 10)
rescue Errno::EACCES # already niced to 11 or more
end

File.umask(002)
STDIN.reopen("/dev/null", "r")

class Build
  @target_list = []
  def Build.main
    @target_list.each {|t|
      t.make_result
    }
  end

  def Build.def_target(target_name, *args, &block)
    t = ChkBuild::Target.new(target_name, *args, &block)
    @target_list << t
    t
  end

  def self.build_dir() "#{TOP_DIRECTORY}/tmp/build" end
  def self.public_dir() "#{TOP_DIRECTORY}/tmp/public_html" end

  class << Build
    attr_accessor :num_oldbuilds
  end
  Build.num_oldbuilds = 3

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

  FileUtils.mkpath Build.build_dir
  lock_path = "#{Build.build_dir}/.lock"
  LOCK_IO = open(lock_path, File::WRONLY|File::CREAT)
  if LOCK_IO.flock(File::LOCK_EX|File::LOCK_NB) == false
    raise "another chkbuild is running."
  end
  LOCK_IO.truncate(0)
  LOCK_IO.sync = true
  LOCK_IO.close_on_exec = true
  lock_pid = $$
  at_exit {
    File.unlink lock_path if $$ == lock_pid
  }
end

STDOUT.sync = true
