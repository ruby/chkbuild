require 'pathname'

module ChkBuild
  TOP_DIRECTORY = Dir.getwd
  def ChkBuild.build_dir() Pathname.new("#{TOP_DIRECTORY}/tmp/build") end
  def ChkBuild.public_dir() Pathname.new("#{TOP_DIRECTORY}/tmp/public_html") end

  @target_list = []
  def ChkBuild.main_build
    ::Build.lock_start
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
        current_txt = ChkBuild.public_dir + build.depsuffixed_name + 'current.txt'
        if current_txt.exist?
          logfile = ChkBuild::LogFile.read_open(current_txt)
          title = ChkBuild::Title.new(t, logfile)
          title.run_title_hooks
          puts "#{build.depsuffixed_name}:\t#{title.make_title}"
        end
      }
    }
  end

  def ChkBuild.main
    case subcommand = ARGV[0]
    when 'build', nil
      ChkBuild.main_build
    when 'list'
      ChkBuild.main_list
    when 'title'
      ChkBuild.main_title
    else
      puts "unexpected subcommand: #{subcommand}"
      exit 1
    end
  end
end
