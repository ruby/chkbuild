require 'timeout'

module TimeoutCommand
  module_function

  def parse_timeout(arg)
    case arg
    when Integer, Float
      timeout = arg
    when /\A\d+(\.\d+)?s?\z/
      timeout = $&.to_f
    when /\A\d+(\.\d+)?m\z/
      timeout = $&.to_f * 60
    when /\A\d+(\.\d+)?h\z/
      timeout = $&.to_f * 60 * 60
    when /\A\d+(\.\d+)?d\z/
      timeout = $&.to_f * 60 * 60 * 24
    else
      raise ArgumentError, "invalid time: #{time.inspect}"
    end
    timeout
  end

  def kill_processgroup(pgid)
    begin
      Process.kill('INT', -pgid)
      STDERR.puts "timeout: INT signal sent."
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
        STDERR.puts "timeout: #{sig} signal sent."
      }
    rescue Errno::ESRCH # no process i.e. success to kill
    end
  end

  def timeout_command(secs)
    secs = parse_timeout(secs)
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
      STDERR.puts "timeout: #{secs} seconds exceeds."
      Thread.new { Process.wait pid }
      begin
        Process.kill(0, -pid)
        STDERR.puts "timeout: the process group is alive."
        kill_processgroup(pid)
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

