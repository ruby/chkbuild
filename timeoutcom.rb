class CommandTimeoutError < StandardError
end

module TimeoutCommand

  module_function

  def parse_timespan(arg)
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
      raise ArgumentError, "invalid time span: #{arg.inspect}"
    end
    timeout
  end

  def kill_processgroup(pgid, msgout)
    begin
      Process.kill('INT', -pgid)
      msgout.puts "timeout: INT signal sent." if msgout
      signals = ['INT', 'TERM', 'TERM', 'KILL']
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

  def process_alive?(pid)
    begin
      Process.kill(0, pid)
    rescue Errno::ESRCH # no process
      return false
    end
    return true
  end

  def processgroup_alive?(pgid)
    process_alive?(-pgid)
  end

  def last_output_time
    last_output_time = [STDOUT, STDERR].map {|f|
      s = f.stat
      if s.file?
        s.mtime
      else
        nil
      end
    }.compact
    if last_output_time.empty?
      nil
    else
      last_output_time.max
    end
  end

  def timeout_command(command_timeout, msgout=STDERR, opts={})
    command_timeout = parse_timespan(command_timeout)
    output_interval_timeout = nil
    if opts[:output_interval_timeout]
      output_interval_timeout = parse_timespan(opts[:output_interval_timeout])
    end
    if command_timeout < 0
      raise CommandTimeoutError, 'no time to run a command'
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
    wait_thread = Thread.new {
      Process.wait2(pid)[1]
    }
    begin
      start_time = Time.now
      limit_time = start_time + command_timeout
      command_status = nil
      while true
        join_timeout = limit_time - Time.now
        if join_timeout < 0
          timeout_reason = "command execution time exceeds #{command_timeout} seconds."
          break 
        end
        if output_interval_timeout and
           t = last_output_time and
           (tmp_join_timeout = t + output_interval_timeout - Time.now) < join_timeout
          join_timeout = tmp_join_timeout
          if join_timeout < 0
            timeout_reason = "output interval exceeds #{output_interval_timeout} seconds."
            break
          end
        end
        if wait_thread.join(join_timeout)
          command_status = wait_thread.value
          break
        end
      end
      if command_status
        return command_status
      else
        msgout.puts "timeout: #{timeout_reason}" if msgout
        begin
          Process.kill(0, -pid)
          msgout.puts "timeout: the process group is alive." if msgout
          kill_processgroup(pid, msgout)
        rescue Errno::ESRCH # no process
        end
        raise CommandTimeoutError, timeout_reason
      end
    rescue Interrupt
      Process.kill("INT", -pid)
      raise
    rescue SignalException
      Process.kill($!.message, -pid)
      raise
    ensure
      if processgroup_alive?(pid)
        msgout.puts "some descendant processes remain." if msgout
        kill_processgroup(pid, msgout)
      end
    end
  end
end

