require 'timeout'

module TimeoutCommand
  module_function

  def parse_timeout(arg)
    case arg
    when Integer, Float
      timeout = arg
    when Time
      timeout = arg - Time.now
    when /\A\d+(\.\d+)?(?:s|sec)?\z/
      timeout = $&.to_f
    when /\A\d+(\.\d+)?(?:m|min)\z/
      timeout = $&.to_f * 60
    when /\A\d+(\.\d+)?(?:h|hour)\z/
      timeout = $&.to_f * 60 * 60
    when /\A\d+(\.\d+)?(?:d|day)\z/
      timeout = $&.to_f * 60 * 60 * 24
    else
      raise ArgumentError, "invalid time: #{arg.inspect}"
    end
    timeout
  end

  def kill_processgroup(pgid, msgout)
    begin
      Process.kill('INT', -pgid)
      msgout.puts "timeout: INT signal sent." if msgout
      signals = ['TERM', 'KILL']
      signals.each {|sig|
        Process.kill(0, -pgid); sleep 0.1
        Process.kill(0, -pgid); sleep 0.2
        Process.kill(0, -pgid); sleep 0.3
        Process.kill(0, -pgid); sleep 0.4
        Process.kill(0, -pgid)
        4.times {
          sleep 1
          Process.kill(0, -pgid)
        }
        Process.kill(sig, -pgid)
        msgout.puts "timeout: #{sig} signal sent." if msgout
      }
    rescue Errno::ESRCH # no process i.e. success to kill
    end
  end

  def timeout_command(secs, msgout=STDERR)
    secs = parse_timeout(secs)
    if secs < 0
      raise TimeoutError, 'no time to run a command'
    end
    pid = fork {
      Process.setpgid($$, $$)
      yield
    }
    begin
      Process.setpgid(pid, pid)
    rescue Errno::EACCES # already execed.
    rescue Errno::ESRCH # already exited. (setpgid for a zombie fails on OpenBSD)
    end
    begin
      timeout(secs) { Process.wait pid }
    rescue TimeoutError
      msgout.puts "timeout: #{secs} seconds exceeds." if msgout
      Thread.new { Process.wait pid }
      begin
        Process.kill(0, -pid)
        msgout.puts "timeout: the process group is alive." if msgout
        kill_processgroup(pid, msgout)
      rescue Errno::ESRCH # no process
      end
      raise
    rescue Interrupt
      Process.kill("INT", -pid)
      raise
    rescue SignalException
      Process.kill($!.message, -pid)
      raise
    end
  end
end

