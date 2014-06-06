# timeoutcom.rb - command timeout library
#
# Copyright (C) 2005-2012 Tanaka Akira  <akr@fsij.org>
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

require 'rbconfig'

class CommandTimeout < StandardError
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

  def last_output_time(file_list=[STDOUT, STDERR])
    last_output_time = file_list.map {|f|
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

  def show_process_group(msg, pgid, msgout)
    return if !msgout
    msgbuf = ''
    # ps -A and -o option is defined by POSIX.
    # However MirOS BSD (MirBSD 10 GENERIC#1382 i386) don't have -A and -ax can be used instead.
    #
    # COLUMNS is described for ps command in POSIX.
    # FreeBSD 8.2 ps uses COLUMNS even for pipe output.
    # GNU/Linux (Debian squeeze) ps doesn't use COLUMNS for pipe output, though.
    #
    ps_all_process_option = '-A'
    case RUBY_PLATFORM
    when /\bmirbsd/
      ps_all_process_option = '-ax'
    end
    ps_additional_options = ''
    case RUBY_PLATFORM
    when /\blinux\b/
      ps_additional_options << ' -L' # show threads
    end
    psresult = IO.popen("COLUMNS=10240 ps #{ps_all_process_option}#{ps_additional_options} -o 'pgid pid etime pcpu vsz comm args'") {|psio|
      psio.to_a
    }
    ps_header, *processes = psresult
    return if !ps_header
    pat = /\A\s*#{pgid}\b/
    processes = processes.grep(pat)
    return if processes.empty?
    msgbuf << "PSOUT #{ps_header}"
    pids = []
    processes.each {|line|
      msgbuf << "PSOUT #{line}"
      if /\A\s*\d+\s+(\d+)/ =~ line
        pids << $1
      end
    }
    if !pids.empty?
      lsof_command = "lsof -p #{pids.join(',')}"
      begin
        lsofresult = `#{lsof_command}`
      rescue Errno::ENOENT
        lsofresult = nil
      end
      if lsofresult
        lsofresult.each_line {|line|
          msgbuf << "LSOFOUT #{line}"
        }
      end
    end
    msgout.puts msg
    msgout.puts msgbuf
  end

  def timeout_command(ruby_script, output_filename, command_timeout, msgout=STDERR, opts={})
    command_timeout = parse_timespan(command_timeout)
    output_interval_timeout = nil
    output_line_max = nil
    if opts[:output_interval_timeout]
      output_interval_timeout = parse_timespan(opts[:output_interval_timeout])
    end
    if opts[:output_line_max]
      output_line_max = opts[:output_line_max]
    end
    process_remain_timeout = nil
    if opts[:process_remain_timeout]
      process_remain_timeout = parse_timespan(opts[:process_remain_timeout])
    end
    file_list = opts[:output_interval_file_list] || [STDOUT, STDERR]
    if command_timeout < 0
      raise CommandTimeout, 'no time to run a command'
    end
    IO.popen(RbConfig.ruby, "w") {|io|
      pid = io.pid
      io.puts 'STDIN.reopen("/dev/null", "r")'
      io.puts "open(#{output_filename.to_s.dump}, File::RDWR|File::CREAT|File::APPEND) {|f|"
      io.puts '  STDOUT.reopen(f)'
      io.puts '  STDERR.reopen(f)'
      io.puts '  STDOUT.sync = true'
      io.puts '  STDERR.sync = true'
      io.puts '}'
      io.puts "Process.setpgid($$, $$)"
      io.puts ruby_script
      io.puts '__END__'
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
	  now = Time.now
          if limit_time < now
            timeout_reason = "command execution time exceeds #{command_timeout} seconds."
            break
          end
          if output_interval_timeout and
             t = last_output_time(file_list) and
	     t + output_interval_timeout < now
	    timeout_reason = "output interval exceeds #{output_interval_timeout} seconds."
	    break
          end
	  if open(output_filename, "r") {|f| output_line_max < f.stat.size and f.seek(-output_line_max, IO::SEEK_END) and /\n/ !~ f.read }
	    timeout_reason = "too long line. (#{output_line_max} bytes at least.)"
	    break
	  end
          if wait_thread.join(1.0)
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
            show_process_group("timeout: the process group #{pid} is alive.", pid, msgout)
            kill_processgroup(pid, msgout)
          rescue Errno::ESRCH # no process
          end
          raise CommandTimeout, timeout_reason
        end
      rescue Interrupt
        Process.kill("INT", -pid)
        raise
      rescue SignalException
        Process.kill($!.message, -pid)
        raise
      ensure
        if processgroup_alive?(pid)
          show_process_group("some descendant process in process group #{pid} remain.", pid, msgout)
	  if process_remain_timeout
	    timelimit = Time.now + process_remain_timeout
	    timeout_reason = opts[:process_remain_timeout]
	    while Time.now < timelimit
	      sleep 1
	      if !processgroup_alive?(pid)
		timeout_reason = nil
		break
	      end
	    end
	    msgout.puts "timeout: #{timeout_reason}" if msgout && timeout_reason
	  end
          kill_processgroup(pid, msgout)
        end
      end
    }
  end
end

