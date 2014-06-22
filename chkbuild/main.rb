# chkbuild/main.rb - chkbuild main routines.
#
# Copyright (C) 2006-2011 Tanaka Akira  <akr@fsij.org>
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
  TOP_DIRECTORY = Pathname.new(__FILE__).realpath.dirname.dirname
  SAMPLE_DIRECTORY = TOP_DIRECTORY + 'sample'
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
  #{command} help
  #{command} [build [--procmemsize] [depsuffixed_name...]]
  #{command} list
  #{command} options [depsuffixed_name...]
  #{command} title [depsuffixed_name...]
  #{command} logdiff [depsuffixed_name [date1 [date2]]]
  #{command} logsubst [depsuffixed_name [date]]
  #{command} logfail [depsuffixed_name [date]]
End
    exit status
  end

  @target_list = []

  def ChkBuild.each_target_build(last_target=@target_list.last)
    build_set = last_target.make_build_set
    build_set.each {|t, builds|
      builds.each {|build|
        yield t, build
      }
    }
  end

  def ChkBuild.main_build
    o = OptionParser.new
    use_procmemsize = false
    o.def_option('--procmemsize') {
      use_procmemsize = true
    }
    o.parse!
    File.umask(002)
    STDIN.reopen("/dev/null", "r")
    STDOUT.sync = true
    ChkBuild.build_top.mkpath
    ChkBuild.lock_start
    each_target_build {|t, build|
      next if !(ARGV.empty? || ARGV.include?(build.depsuffixed_name))
      build.update_option(:procmemsize => true) if use_procmemsize
      if build.depbuilds.all? {|depbuild| depbuild.success? }
	build.build
      end
    }
  end

  def ChkBuild.main_internal_build
    format_params_name = ARGV.shift
    File.umask(002)
    STDIN.reopen("/dev/null", "r")
    STDOUT.sync = true
    ChkBuild.build_top.mkpath
    ibuild = File.open(format_params_name) {|f| Marshal.load(f) }
    ibuild.internal_build
    exit 1
  end

  def ChkBuild.main_internal_format
    format_params_name = ARGV.shift
    File.umask(002)
    STDIN.reopen("/dev/null", "r")
    STDOUT.sync = true
    ChkBuild.build_top.mkpath
    iformat = File.open(format_params_name) {|f| Marshal.load(f) }
    iformat.internal_format
    exit 1
  end

  def ChkBuild.def_target(target_name, *args, &block)
    t = ChkBuild::Target.new(target_name, *args, &block)
    @target_list << t
    t
  end

  def ChkBuild.main_list
    each_target_build {|t, build|
      puts build.depsuffixed_name
    }
  end

  def ChkBuild.main_options
    each_target_build {|t, build|
      next if !ARGV.empty? && !ARGV.include?(build.depsuffixed_name)
      puts build.depsuffixed_name
      opts = build.opts
      if opts[:complete_options] && opts[:complete_options].respond_to?(:merge_dependencies)
	dep_dirs = []
	build.depbuilds.each {|depbuild|
	  dir = ChkBuild.build_top + depbuild.depsuffixed_name + "<time>"
	  dep_dirs << "#{depbuild.target.target_name}=#{dir}"
	}
	opts = opts[:complete_options].merge_dependencies(opts, dep_dirs)
      end
      opts.keys.sort_by {|k| k.to_s }.each {|k|
	v = opts[k]
	puts "option #{k.inspect} => #{v.inspect}"
      }
      puts
    }
  end

  def ChkBuild.main_title
    each_target_build {|t, build|
      next if !ARGV.empty? && !ARGV.include?(build.depsuffixed_name)
      last_txt = ChkBuild.public_top + build.depsuffixed_name + 'last.txt'
      if last_txt.exist?
	logfile = ChkBuild::LogFile.read_open(last_txt)
	title = ChkBuild::Title.new(t, logfile)
	title.run_hooks
	puts "#{build.depsuffixed_name}:\t#{title.make_title}"
      end
    }
  end

  def ChkBuild.main_logdiff
    depsuffixed_name, arg_t1, arg_t2 = ARGV
    each_target_build {|t, build|
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
      iformat = build.iformat_new(t1)
      iformat.output_diff(t1, t2, STDOUT)
      puts
    }
  end

  def ChkBuild.main_logsubst
    depsuffixed_name, arg_t = ARGV
    each_target_build {|t, build|
      next if depsuffixed_name && build.depsuffixed_name != depsuffixed_name
      ts = build.log_time_sequence
      raise "no log: #{build.depsuffixed_name}/#{arg_t}" if arg_t and !ts.include?(arg_t)
      t = arg_t || ts[-1]
      puts "#{build.depsuffixed_name}: #{t}"
      iformat = build.iformat_new(t)
      tmp = iformat.make_diff_content(t)
      tmp.rewind
      IO.copy_stream(tmp, STDOUT)
    }
  end

  def ChkBuild.main_logfail
    depsuffixed_name, arg_t = ARGV
    each_target_build {|t, build|
      next if depsuffixed_name && build.depsuffixed_name != depsuffixed_name
      ts = build.log_time_sequence
      raise "no log: #{build.depsuffixed_name}/#{arg_t}" if arg_t and !ts.include?(arg_t)
      if ts.empty?
	puts "#{build.depsuffixed_name}: no logs"
	next
      end
      t = arg_t || ts[-1]
      puts "#{build.depsuffixed_name}: #{t}"
      iformat = build.iformat_new(t)
      iformat.output_fail(t, STDOUT)
      puts
    }
  end

  def ChkBuild.main
    ARGV.unshift 'build' if ARGV.empty?
    subcommand = ARGV.shift
    case subcommand
    when 'help', '-h' then ChkBuild.main_help
    when 'build' then ChkBuild.main_build
    when 'internal-build' then ChkBuild.main_internal_build
    when 'internal-format' then ChkBuild.main_internal_format
    when 'list' then ChkBuild.main_list
    when 'options' then ChkBuild.main_options
    when 'title' then ChkBuild.main_title
    when 'logdiff' then ChkBuild.main_logdiff
    when 'logsubst' then ChkBuild.main_logsubst
    when 'logfail' then ChkBuild.main_logfail
    else
      puts "unexpected subcommand: #{subcommand}"
      exit 1
    end
  end
end
