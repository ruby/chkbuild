# chkbuild/lock.rb - lock implementation
#
# Copyright (C) 2006,2009,2010 Tanaka Akira  <akr@fsij.org>
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

module ChkBuild
  LOCK_PATH = ChkBuild.build_top + '.lock'

  def self.lock_start
    if !defined?(@lock_io)
      @lock_io = LOCK_PATH.open(File::WRONLY|File::CREAT|File::APPEND)
    end
    if @lock_io.flock(File::LOCK_EX|File::LOCK_NB) == false
      raise "another chkbuild is running."
    end
    if 102400 < @lock_io.stat.size
      @lock_io.truncate(0)
    end
    @lock_io.sync = true
    @lock_io.close_on_exec = true
    @lock_io.puts "\n#{Time.now.iso8601} locked pid:#{$$}"
    lock_pid = $$
    t1 = Time.now
    at_exit {
      t2 = Time.now
      @lock_io.print "#{Time.now.iso8601} exit pid:#{$$}\t#{Util.format_elapsed_time t2-t1}\n" if $$ == lock_pid
    }
  end

  def self.lock_puts(mesg)
    LOCK_PATH.open(File::WRONLY|File::APPEND) {|f|
      f.sync = true
      if block_given?
        t1 = Time.now
        f.print "#{t1.iso8601} #{mesg}"
        ret = yield
        t2 = Time.now
        f.puts "\t#{ret.inspect}\t#{Util.format_elapsed_time t2-t1}"
        ret
      else
        f.puts "#{Time.now.iso8601} #{mesg}"
      end
    }
  end
end
