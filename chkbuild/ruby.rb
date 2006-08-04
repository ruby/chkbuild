require 'build'

def def_build_ruby(*args)
  def_build_ruby_internal(false, *args)
end

def def_build_ruby2(*args)
  def_build_ruby_internal(true, *args)
end

def def_build_ruby_internal(separated_dir, *args)
  b = Build.def_target("ruby", *args) {|b, *suffixes|
    ruby_work_dir = b.work_dir

    ruby_branch = nil
    configure_flags = []
    cflags = %w{-Wall -Wformat=2 -Wno-parentheses -g -O2 -DRUBY_GC_STRESS}
    gcc_dir = nil
    autoconf_command = 'autoconf'
    make_options = {}
    suffixes.each {|s|
      case s
      when "trunk" then ruby_branch = nil
      when "1.8" then ruby_branch = 'ruby_1_8'
      when "o0"
        cflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
        cflags << '-O0'
      when "o1"
        cflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
        cflags << '-O1'
      when "o3"
        cflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
        cflags << '-O3'
      when "pth" then configure_flags << '--enable-pthread'
      when /\Agcc=/
        configure_flags << "CC=#{$'}/bin/gcc"
        make_options["ENV:LD_RUN_PATH"] = "#{$'}/lib"
      when /\Aautoconf=/
        autoconf_command = "#{$'}/bin/autoconf"
      else
        raise "unexpected suffix: #{s.inspect}"
      end
    }

    objdir = ruby_work_dir+'ruby'
    if separated_dir
      checkout_dir = ruby_work_dir.dirname
    else
      checkout_dir = ruby_work_dir
    end
    srcdir = (checkout_dir+'ruby').relative_path_from(objdir)

    Dir.chdir(checkout_dir)
    b.cvs(
      ":pserver:anonymous@cvs.ruby-lang.org:/src", "ruby", ruby_branch,
      :cvsweb => "http://www.ruby-lang.org/cgi-bin/cvsweb.cgi"
      )
    Dir.chdir("ruby")
    b.run(autoconf_command)

    Dir.chdir(ruby_work_dir)
    b.mkcd("ruby")
    b.run("#{srcdir}/configure", "--prefix=#{ruby_work_dir}", "CFLAGS=#{cflags.join(' ')}", *configure_flags)
    b.make(make_options)
    b.run("./ruby", "-v", :section=>"version")
    b.make("install")
    b.run("./ruby", "#{srcdir+'sample/test.rb'}", :section=>"test.rb")
    b.run("./ruby", "#{srcdir+'test/runner.rb'}", "-v", :section=>"test-all")
  }

  b.add_title_hook("configure") {|bb, log|
    if /^checking target system type\.\.\. (\S+)$/ =~ log
      b.update_title(:version, "#{b.suffixed_name} [#{$1}]")
    end
  }

  b.add_title_hook("version") {|bb, log|
    if /^ruby [0-9.]+ \([0-9\-]+\) \[\S+\]$/ =~ log
      ver = $&
      ss = b.suffixes.reject {|s| /\A(pth|o\d)\z/ !~ s }
      ver << " [#{ss.join(',')}]" if !ss.empty?
      b.update_title(:version, ver)
    end
  }
    
  b.add_title_hook("test.rb") {|bb, log|
    b.update_title(:status) {|val|
      if /^end of test/ !~ log
        if /^test: \d+ failed (\d+)/ =~ log
          "#{$1}NotOK"
        end
      end
    }
  }

  b.add_title_hook("test-all") {|bb, log|
    b.update_title(:status) {|val|
      if /^\d+ tests, \d+ assertions, (\d+) failures, (\d+) errors$/ =~ log
        failures = $1.to_i
        errors = $2.to_i
        if failures != 0 || errors != 0
          "#{failures}F#{errors}E"
        end
      end
    }
  }

  b.add_title_hook("end") {
    log = b.all_log
    mark = ''
    mark << "[BUG]" if /\[BUG\]/i =~ log
    mark << "[SEGV]" if /segmentation fault|signal segv/i =~
      log.sub(/combination may cause frequent hang or segmentation fault/, '') # skip tk message.
    mark << "[FATAL]" if /\[FATAL\]/i =~ log
    b.update_title(:mark, mark)
  }

  b
end
