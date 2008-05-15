require 'chkbuild'

module ChkBuild
  module Ruby
    METHOD_LIST_SCRIPT = <<'End'
nummodule = nummethod = 0
mods = []
ObjectSpace.each_object(Module) {|m| mods << m if m.name }
mods = mods.sort_by {|m| m.name }
mods.each {|mod|
  nummodule += 1
  puts "#{mod.name} #{(mod.ancestors - [mod]).inspect}"
  mod.singleton_methods(false).sort.each {|methname|
    nummethod += 1
    meth = mod.method(methname)
    puts "#{mod.name}.#{methname} #{meth.arity}"
  }
  mod.instance_methods(false).sort.each {|methname|
    nummethod += 1
    meth = mod.instance_method(methname)
    puts "#{mod.name}\##{methname} #{meth.arity}"
  }
}
puts "#{nummodule} modules, #{nummethod} methods"
End

    # not strictly RFC 1034.
    DOMAINLABEL = /[A-Za-z0-9-]+/
    DOMAINPAT = /#{DOMAINLABEL}(\.#{DOMAINLABEL})*/

    module_function

    def limit_combination(*suffixes)
      return false if suffixes.include?("trunk") && suffixes.include?("pth")
      return false if suffixes.include?("half-baked-1.9") && suffixes.include?("pth")
      true
    end

    MaintainedBranches = %w[trunk 1.8 1.8.7 1.8.6 1.8.5]

    def def_target(*args)
      opts = Hash === args.last ? args.pop : {}
      default_opts = {:separated_srcdir=>false}
      opts = default_opts.merge(opts)
      opts[:limit_combination] = method(:limit_combination)
      args.push opts
      opts = Hash === args.last ? args.last : {}
      separated_srcdir = opts[:separated_srcdir]
      t = ChkBuild.def_target("ruby", *args) {|b, *suffixes|
        ruby_build_dir = b.build_dir

        ruby_branch = nil
        configure_flags = %w[--with-valgrind]
        cflags = %w[-Wall -Wformat=2 -Wundef -Wno-parentheses -g -O2 -DRUBY_DEBUG_ENV]
	dldflags = %w[]
        gcc_dir = nil
        autoconf_command = 'autoconf'
        make_options = {}
        suffixes.each {|s|
          case s
          when "trunk" then ruby_branch = 'trunk'
          when "half-baked-1.9" then ruby_branch = 'branches/half-baked-1.9'
          when "matzruby" then ruby_branch = 'branches/matzruby'
          when "1.8" then ruby_branch = 'branches/ruby_1_8'
          when "1.8.5" then ruby_branch = 'branches/ruby_1_8_5'
          when "1.8.6" then ruby_branch = 'branches/ruby_1_8_6'
          when "1.8.7" then ruby_branch = 'branches/ruby_1_8_7'
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
          when "m32"
            cflags.delete_if {|arg| /\A-m(32|64)\z/ =~ arg }
            cflags << '-m32'
            dldflags.delete_if {|arg| /\A-m(32|64)\z/ =~ arg }
            dldflags << '-m32'
          when "m64"
            cflags.delete_if {|arg| /\A-m(32|64)\z/ =~ arg }
            cflags << '-m64'
            dldflags.delete_if {|arg| /\A-m(32|64)\z/ =~ arg }
            dldflags << '-m64'
          when /\Agcc=/
            configure_flags << "CC=#{$'}/bin/gcc"
            make_options["ENV:LD_RUN_PATH"] = "#{$'}/lib"
          when /\Aautoconf=/
            autoconf_command = "#{$'}/bin/autoconf"
          else
            raise "unexpected suffix: #{s.inspect}"
          end
        }

        use_rubyspec = false
        if %r{branches/ruby_1_8} =~ ruby_branch &&
           ENV['PATH'].split(/:/).any? {|d| File.executable?("#{d}/git") }
          use_rubyspec = true
        end

        objdir = ruby_build_dir+'ruby'
        if separated_srcdir
          checkout_dir = ruby_build_dir.dirname
        else
          checkout_dir = ruby_build_dir
        end
        srcdir = (checkout_dir+'ruby').relative_path_from(objdir)

        Dir.chdir(checkout_dir)
        b.svn("http://svn.ruby-lang.org/repos/ruby", ruby_branch, 'ruby',
          :viewvc=>'http://svn.ruby-lang.org/cgi-bin/viewvc.cgi?diff_format=u')
        Dir.chdir("ruby")
        b.run(autoconf_command)

        Dir.chdir(ruby_build_dir)

        use_rubyspec &&= b.catch_error {
          b.run("git", "clone", "-q", "git://github.com/brixen/mspec.git")
        }
        use_rubyspec &&= b.catch_error {
          b.run("git", "clone", "-q", "git://github.com/brixen/rubyspec.git", "spec/rubyspec")
        }

        b.mkcd("ruby")
	args = []
	args << "--prefix=#{ruby_build_dir}"
	args << "CFLAGS=#{cflags.join(' ')}"
	args << "DLDFLAGS=#{dldflags.join(' ')}" unless dldflags.empty?
	args.concat configure_flags
        b.run("#{srcdir}/configure", *args)
        b.make("miniruby", make_options)
        b.catch_error { b.run("./miniruby", "-v", :section=>"version") }
        if (File.directory? "#{srcdir}/bootstraptest")
          b.catch_error { b.make("btest", "OPTS=-v -q", :section=>"btest") }
        end
        b.catch_error {
          b.run("./miniruby", "#{srcdir+'sample/test.rb'}", :section=>"test.rb")
          if /^end of test/ !~ b.logfile.get_section('test.rb')
            raise ChkBuild::Build::CommandError.new(0, "test.rb")
          end
        }
        b.catch_error { b.run("./miniruby", '-e', METHOD_LIST_SCRIPT, :section=>"method-list") }
        b.make(make_options)
        b.make("install-nodoc")
        b.catch_error { b.make("install-doc") }
        #b.catch_error { b.run("./ruby", "#{srcdir+'test/runner.rb'}", "-v", :section=>"test-all") }
        b.catch_error { b.make("test-all", "TESTS=-v", :section=>"test-all") }

        Dir.chdir(ruby_build_dir)
        use_rubyspec &&= b.catch_error {
          b.run("/usr/bin/ruby", "mspec/bin/mspec", "--verbose", "-t", "bin/ruby", "spec/rubyspec/1.8", :section=>"rubyspec")
        }
      }

      t.add_title_hook("configure") {|title, log|
        if /^checking target system type\.\.\. (\S+)$/ =~ log
          title.update_title(:version, "#{title.suffixed_name} [#{$1}]")
        end
      }

      t.add_title_hook("version") {|title, log|
        if /^ruby [0-9.]+ \([0-9a-z \-]+\) \[\S+\]$/ =~ log
          ver = $&
          ss = title.suffixed_name.split(/-/)[1..-1].reject {|s| /\A(trunk|1\.8)\z/ =~ s }
          ver << " [#{ss.join(',')}]" if !ss.empty?
          title.update_title(:version, ver)
        end
      }

      t.add_failure_hook("btest") {|log|
        if /^FAIL (\d+)\/\d+ tests failed/ =~ log
          "#{$1}BFail"
        end
      }

      t.add_failure_hook("test.rb") {|log|
        if /^end of test/ !~ log
          if /^test: \d+ failed (\d+)/ =~ log || %r{^not ok/test: \d+ failed (\d+)} =~ log
            "#{$1}NotOK"
          end
        end
      }

      t.add_failure_hook("test-all") {|log|
        if /^\d+ tests, \d+ assertions, (\d+) failures, (\d+) errors$/ =~ log
          failures = $1.to_i
          errors = $2.to_i
          if failures != 0 || errors != 0
            "#{failures}F#{errors}E"
          end
        end
      }

      t.add_title_hook(nil) {|title, log|
        mark = ''
        numbugs = count_prefix(/\[BUG\]/i, log) and mark << " #{numbugs}[BUG]"
        numsegv = count_prefix(
          /segmentation fault|signal segv/i,
          log.sub(/combination may cause frequent hang or segmentation fault/, '')) and # skip tk message.
          mark << " #{numsegv}[SEGV]"
        numsigbus = count_prefix(/signal SIGBUS/i, log) and mark << " #{numsigbus}[SIGBUS]"
        numsigill = count_prefix(/signal SIGILL/i, log) and mark << " #{numsigill}[SIGILL]"
        numsigabrt = count_prefix(/signal SIGABRT/i, log) and mark << " #{numsigabrt}[SIGABRT]"
        numfatal = count_prefix(/\[FATAL\]/i, log) and mark << " #{numfatal}[FATAL]" 
        mark.sub!(/\A /, '')
        title.update_title(:mark, mark)
      }

      # test_exception.rb #1 test_exception.rb:1
      t.add_diff_preprocess_gsub(/\#\d+ test_/) {|match|
        "#<n> test_"
      }

      t.add_diff_preprocess_gsub(/^ *\d+\) (Error:|Failure:)/) {|match|
        " <n>) #{match[1]}"
      }

      t.add_diff_preprocess_gsub(%r{\((druby|drbssl)://(#{DOMAINPAT}):\d+\)}o) {|match|
        "(#{match[1]}://#{match[2]}:<port>)"
      }

      # [2006-09-24T12:48:49.245737 #6902] ERROR -- : undefined method `each' for #<String:0x447fc5e4> (NoMethodError)
      t.add_diff_preprocess_gsub(%r{\[\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+) \#(\d+)\]}o) {|match|
        "[YYYY-MM-DDThh:mm:ss" + match[1].gsub(/\d/, 's') + " #<pid>]"
      }

      # #<String:0x4455ae94
      t.add_diff_preprocess_gsub(%r{\#<[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*:0x[0-9a-f]+}o) {|match|
        match[0].sub(/[0-9a-f]+\z/) { 'X' * $&.length }
      }

      # #<#<Class:0xXXXXXXX>:0x0e87dd00
      # order sensitive.  this should be applied after the above.
      t.add_diff_preprocess_gsub(%r{(\#<\#<Class:0xX+>:0x)([0-9a-f]+)}o) {|match|
        match[1] + 'X' * match[2].length
      }

      # XSD::ValueSpaceError: {http://www.w3.org/2001/XMLSchema}dateTime: cannot accept '2007-02-01T23:44:2682967.846399999994901+09:00'.
      t.add_diff_preprocess_gsub(%r{\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\d+\.\d+}o) {|match|
        s = match[0]
        chars = %w[Y M D h m s s]
        s.gsub!(/\d+/) { "<#{chars.shift}>" }
        s
      }

      t.add_diff_preprocess_gsub(/^Elapsed: [0-9.]+s/) {|match|
        "Elapsed: <t>s"
      }

      t.add_diff_preprocess_gsub(/^Finished in [0-9.]+ seconds\./) {|match|
        "Finished in <t> seconds."
      }

      # /tmp/test_rubygems_18634
      t.add_diff_preprocess_gsub(%r{/tmp/test_rubygems_\d+}o) {|match|
        '/tmp/test_rubygems_<pid>'
      }

      t
    end

    def count_prefix(pat, str)
      n = 0
      str.scan(pat) { n += 1 }
      case n
      when 0
        nil
      when 1
        ""
      else
        n.to_s
      end
    end
  end
end
