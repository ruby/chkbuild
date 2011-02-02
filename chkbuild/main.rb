# chkbuild/main.rb - chkbuild main routines.
#
# Copyright (C) 2006-2011 Tanaka Akira  <akr@fsij.org>
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#  3. The name of the author may not be used to endorse or promote products
#     derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
# OF SUCH DAMAGE.

require 'pathname'
require 'optparse'

module ChkBuild
  TOP_DIRECTORY = Pathname.new(__FILE__).realpath.dirname.dirname
  def ChkBuild.build_top() TOP_DIRECTORY+"tmp/build" end
  def ChkBuild.public_top() TOP_DIRECTORY+"tmp/public_html" end

  def ChkBuild.main_help(status=true)
    if File.executable? $0
      command = $0
    else
      require 'rbconfig'
      ruby = "#{Config::CONFIG["bindir"]}/#{Config::CONFIG["ruby_install_name"]}"
      command = "#{ruby} #{$0}"
    end
    print <<"End"
usage:
  #{command} [build [--procmemsize] [depsuffixed_name...]]
  #{command} list
  #{command} title [depsuffixed_name...]
  #{command} logdiff [depsuffixed_name [date1 [date2]]]
End
    exit status
  end

  @target_list = []

  def ChkBuild.main_build
    o = OptionParser.new
    o.def_option('--procmemsize') {
      @target_list.each {|t|
        t.update_option(:procmemsize => true)
      }
    }
    o.parse!
    begin
      Process.setpriority(Process::PRIO_PROCESS, 0, 10)
    rescue Errno::EACCES # already niced to 11 or more
    end
    File.umask(002)
    STDIN.reopen("/dev/null", "r")
    STDOUT.sync = true
    ChkBuild.build_top.mkpath
    ChkBuild.lock_start
    @target_list.each {|t|
      t.make_result {|b|
        if ARGV.empty?
          true
        else
          ARGV.include?(b.depsuffixed_name)
        end
      }
    }
  end

  def ChkBuild.main_internal_build
    o = OptionParser.new
    o.def_option('--procmemsize') {
      @target_list.each {|t|
        t.update_option(:procmemsize => true)
      }
    }
    o.parse!
    depsuffixed_name = ARGV.shift
    start_time = ARGV.shift
    target_params_name = ARGV.shift
    target_output_name = ARGV.shift
    begin
      Process.setpriority(Process::PRIO_PROCESS, 0, 10)
    rescue Errno::EACCES # already niced to 11 or more
    end
    File.umask(002)
    STDIN.reopen("/dev/null", "r")
    STDOUT.sync = true
    ChkBuild.build_top.mkpath
    @target_list.each {|t|
      t.each_build_obj {|build|
        if build.depsuffixed_name == depsuffixed_name
          build.internal_build start_time, target_params_name, target_output_name
        end
      }
    }
    exit 1
  end

  def ChkBuild.def_target(target_name, *args, &block)
    t = ChkBuild::Target.new(target_name, *args, &block)
    @target_list << t
    t
  end

  def ChkBuild.main_list
    @target_list.each {|t|
      t.each_build_obj {|build|
        puts build.depsuffixed_name
      }
    }
  end

  def ChkBuild.main_options
    @target_list.each {|t|
      t.each_build_obj {|build|
        puts build.depsuffixed_name
	pp build.opts
      }
    }
  end

  def ChkBuild.main_title
    @target_list.each {|t|
      t.each_build_obj {|build|
        next if !ARGV.empty? && !ARGV.include?(build.depsuffixed_name)
        last_txt = ChkBuild.public_top + build.depsuffixed_name + 'last.txt'
        if last_txt.exist?
          logfile = ChkBuild::LogFile.read_open(last_txt)
          title = ChkBuild::Title.new(t, logfile)
          title.run_hooks
          puts "#{build.depsuffixed_name}:\t#{title.make_title}"
        end
      }
    }
  end

  def ChkBuild.main_logdiff
    depsuffixed_name, arg_t1, arg_t2 = ARGV
    @target_list.each {|t|
      t.each_build_obj {|build|
        next if depsuffixed_name && build.depsuffixed_name != depsuffixed_name
        ts = build.log_time_sequence
        raise "no log: #{build.depsuffixed_name}/#{arg_t1}" if arg_t1 and !ts.include?(arg_t1)
        raise "no log: #{build.depsuffixed_name}/#{arg_t2}" if arg_t2 and !ts.include?(arg_t2)
        if ts.length < 2
          puts "#{build.depsuffixed_name}: less than 2 logs"
          next
        end
        t1 = arg_t1 || ts[-2]
        t2 = arg_t2 || ts[-1]
        puts "#{build.depsuffixed_name}: #{t1}->#{t2}"
        build.output_diff(t1, t2, STDOUT)
        puts
      }
    }
  end

  def ChkBuild.main
    ARGV.unshift 'build' if ARGV.empty?
    subcommand = ARGV.shift
    case subcommand
    when 'help', '-h' then ChkBuild.main_help
    when 'build' then ChkBuild.main_build
    when 'internal-build' then ChkBuild.main_internal_build
    when 'list' then ChkBuild.main_list
    when 'options' then ChkBuild.main_options
    when 'title' then ChkBuild.main_title
    when 'logdiff' then ChkBuild.main_logdiff
    else
      puts "unexpected subcommand: #{subcommand}"
      exit 1
    end
  end
end
