require 'build'
require 'pathname'

def build_ruby(*args)
  build_ruby_internal(false, *args)
end

def build_ruby2(*args)
  build_ruby_internal(true, *args)
end

def build_ruby_internal(separated_dir, *args)
  Build.perm_target("ruby", *args) {
      |b, ruby_work_dir, *suffixes|
    ruby_work_dir = Pathname.new(ruby_work_dir)
    long_name = ['ruby', *suffixes].join('-')

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
    b.run("#{srcdir}/configure", "--prefix=#{ruby_work_dir}", "CFLAGS=#{cflags.join(' ')}", *configure_flags) {|log|
      if /^checking target system type\.\.\. (\S+)$/ =~ log
        b.update_title(:version, "#{long_name} #{$1}")
      end
    }
    b.add_finish_hook {
      log = b.all_log
      mark = ''
      mark << "[BUG]" if /\[BUG\]/i =~ log
      mark << "[SEGV]" if /segmentation fault|signal segv/i =~
        log.sub(/combination may cause frequent hang or segmentation fault/, '') # skip tk message.
      mark << "[FATAL]" if /\[FATAL\]/i =~ log
      b.update_title(:mark, mark)
    }
    b.make(make_options)
    b.run("./ruby", "-v", :section=>"version") {|log|
      if /^ruby [0-9.]+ \([0-9\-]+\) \[\S+\]$/ =~ log
        b.update_title(:version, $&)
      end
    }
    b.make("install")
    b.run("./ruby", "#{srcdir+'sample/test.rb'}", :section=>"test.rb") {|log|
      b.update_title(:status) {|val|
        if !val
          if /^end of test/ !~ log
            if /^test: \d+ failed (\d+)/ =~ log
              "#{$1}NotOK"
            else
              "SomethingFail"
            end
          end
        end
      }
    }
    b.run("./ruby", "#{srcdir+'test/runner.rb'}", "-v", :section=>"test-all") {|log|
      b.update_title(:status) {|val|
        if !val
          if /^\d+ tests, \d+ assertions, (\d+) failures, (\d+) errors$/ =~ log
            failures = $1.to_i
            errors = $2.to_i
            if failures != 0 || errors != 0
              "#{failures}F#{errors}E"
            end
          else
            "SomethingFail"
          end
        end
      }
    }
  }
end
