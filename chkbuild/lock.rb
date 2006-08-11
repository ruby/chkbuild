module ChkBuild
  LOCK_PATH = ChkBuild.build_top + '.lock'

  def self.lock_start
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

  def self.lock_puts(mesg)
    @lock_io.puts mesg
  end
end
