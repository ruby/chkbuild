require 'pathname'
require 'optparse'

module ChkBuild
  TOP_DIRECTORY = Pathname.getwd
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
  #{command} [build [--procmemsize]]
  #{command} list
  #{command} title [depsuffixed_name...]
  #{command} logdiff [depsuffixed_name...]
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
      t.make_result
    }
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

  def ChkBuild.main_title
    @target_list.each {|t|
      t.each_build_obj {|build|
        next if !ARGV.empty? && !ARGV.include?(build.depsuffixed_name)
        last_txt = ChkBuild.public_top + build.depsuffixed_name + 'last.txt'
        if last_txt.exist?
          logfile = ChkBuild::LogFile.read_open(last_txt)
          title = ChkBuild::Title.new(t, logfile)
          title.run_title_hooks
          puts "#{build.depsuffixed_name}:\t#{title.make_title}"
        end
      }
    }
  end

  def ChkBuild.main_logdiff
    @target_list.each {|t|
      t.each_build_obj {|build|
        next if !ARGV.empty? && !ARGV.include?(build.depsuffixed_name)
        ts = build.log_time_sequence
        if ts.length < 2
          puts "#{build.depsuffixed_name}: less than 2 logs"
        end
        t1, t2 = ts[-2, 2]
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
    when 'list' then ChkBuild.main_list
    when 'title' then ChkBuild.main_title
    when 'logdiff' then ChkBuild.main_logdiff
    else
      puts "unexpected subcommand: #{subcommand}"
      exit 1
    end
  end
end
