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
      |ruby_curr_dir, concatenated_suffix, *suffixes|
    ruby_curr_dir = Pathname.new(ruby_curr_dir)

    ruby_branch = nil
    configure_flags = []
    cflags = ''
    suffixes.each {|s|
      case s
      when "trunk" then ruby_branch = nil
      when "1.8" then ruby_branch = 'ruby_1_8'
      when "pth" then configure_flags = %w{--enable-pthread}
      else raise "unexpected suffix: #{s.inspect}"
      end
    }

    objdir = ruby_curr_dir+'ruby'
    if separated_dir
      checkout_dir = ruby_curr_dir.dirname
    else
      checkout_dir = ruby_curr_dir
    end
    srcdir = (checkout_dir+'ruby').relative_path_from(objdir)

    Dir.chdir(checkout_dir)
    Build.cvs(
      ":pserver:anonymous@cvs.ruby-lang.org:/src", "ruby", ruby_branch,
      :cvsweb => "http://www.ruby-lang.org/cgi-bin/cvsweb.cgi"
      )
    Dir.chdir("ruby")
    Build.run("autoconf")

    Dir.chdir(ruby_curr_dir)
    Build.mkcd("ruby")
    Build.run("#{srcdir}/configure", "--prefix=#{ruby_curr_dir}", "CFLAGS=-Wall -Wformat=2 -Wno-parentheses -g -O2 -DRUBY_GC_STRESS #{cflags}", *configure_flags) {|log|
      if /^checking target system type\.\.\. (\S+)$/ =~ log
        Build.update_title(:version, "#{['ruby', *suffixes].join('-')} #{$1}")
      end
    }
    Build.add_finish_hook {
      log = Build.all_log
      mark = ''
      mark << "[BUG]" if /\[BUG\]/i =~ log
      mark << "[SEGV]" if /segmentation fault|signal segv/i =~
        log.sub(/combination may cause frequent hang or segmentation fault/, '') # skip tk message.
      mark << "[FATAL]" if /\[FATAL\]/i =~ log
      Build.update_title(:mark, mark)
    }
    Build.make
    Build.run("./ruby", "-v", :section=>"version") {|log|
      if /^ruby [0-9.]+ \([0-9\-]+\) \[\S+\]$/ =~ log
        Build.update_title(:version, $&)
      end
    }
    Build.make("install")
    Build.run("./ruby", "#{srcdir+'sample/test.rb'}", :section=>"test.rb") {|log|
      Build.update_title(:status) {|val|
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
    Build.run("./ruby", "#{srcdir+'test/runner.rb'}", "-v", :section=>"test-all") {|log|
      Build.update_title(:status) {|val|
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
