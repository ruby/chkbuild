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
    if block_given?
      t1 = Time.now
      @lock_io.print "#{t1.iso8601} #{mesg}"
      ret = yield
      t2 = Time.now
      @lock_io.puts "\t#{t2-t1}"
      ret
    else
      @lock_io.puts "#{Time.now.iso8601} #{mesg}"
    end
  end
end
