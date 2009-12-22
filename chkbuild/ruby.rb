# chkbuild/ruby.rb - ruby build module
#
# Copyright (C) 2006,2007,2008,2009 Tanaka Akira  <akr@fsij.org>
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

require 'chkbuild'

module ChkBuild
  module Ruby
    METHOD_LIST_SCRIPT = <<'End'
use_symbol = Object.instance_methods[0].is_a?(Symbol)
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
    line = "#{mod.name}.#{methname} #{meth.arity}"
    line << " not-implemented" if !mod.respond_to?(methname)
    puts line
  }
  ms = mod.instance_methods(false)
  if use_symbol
    ms << :initialize if mod.private_instance_methods(false).include? :initialize
  else
    ms << "initialize" if mod.private_instance_methods(false).include? "initialize"
  end
  ms.sort.each {|methname|
    nummethod += 1
    meth = mod.instance_method(methname)
    line = "#{mod.name}\##{methname} #{meth.arity}"
    line << " not-implemented" if /\(not-implemented\)/ =~ meth.inspect
    puts line
  }
}
puts "#{nummodule} modules, #{nummethod} methods"
End

    # not strictly RFC 1034.
    DOMAINLABEL = /[A-Za-z0-9-]+/
    DOMAINPAT = /#{DOMAINLABEL}(\.#{DOMAINLABEL})*/

    module_function

    def limit_combination(*suffixes)
      if suffixes.include?("pth")
        return false if suffixes.grep(/\A1\.8/).empty? && !suffixes.include?("matzruby")
      end
      true
    end

    MaintainedBranches = %w[trunk 1.9.1 1.8 1.8.7 1.8.6]

    def def_target(*args)
      opts = Hash === args.last ? args.pop : {}
      default_opts = {:separated_srcdir=>false, :shared_gitdir=>ChkBuild.build_top}
      opts = default_opts.merge(opts)
      opts[:limit_combination] = method(:limit_combination)
      args.push opts
      opts = Hash === args.last ? args.last : {}
      separated_srcdir = opts[:separated_srcdir]
      t = ChkBuild.def_target("ruby", *args) {|b, *suffixes|
        ruby_build_dir = b.build_dir

        ruby_branch = nil
        configure_flags = %w[--with-valgrind]
        cflags = %w[]
        cppflags = %w[-DRUBY_DEBUG_ENV]
        optflags = %w[-O2]
        debugflags = %w[-g]
	warnflags = %w[-W -Wall -Wformat=2 -Wundef -Wno-parentheses -Wno-unused-parameter -Wno-missing-field-initializers]
	dldflags = %w[]
        gcc_dir = nil
        autoconf_command = 'autoconf'
        make_options = {}
        suffixes.each {|s|
          case s
          when "trunk" then ruby_branch = 'trunk'
          when "mvm" then ruby_branch = 'branches/mvm'
            cppflags.delete '-DRUBY_DEBUG_ENV'
          when "half-baked-1.9" then ruby_branch = 'branches/half-baked-1.9'
          when "matzruby" then ruby_branch = 'branches/matzruby'
          when "1.9.1" then ruby_branch = 'branches/ruby_1_9_1'
          when "1.8" then ruby_branch = 'branches/ruby_1_8'
          when "1.8.5" then ruby_branch = 'branches/ruby_1_8_5'
          when "1.8.6" then ruby_branch = 'branches/ruby_1_8_6'
          when "1.8.7" then ruby_branch = 'branches/ruby_1_8_7'
          when "o0"
            optflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
            optflags << '-O0'
          when "o1"
            optflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
            optflags << '-O1'
          when "o3"
            optflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
            optflags << '-O3'
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

	if opts["--with-opt-dir"]
	  configure_flags << "--with-opt-dir=#{opts['--with-opt-dir']}"
	end

	if %r{branches/ruby_1_8_} =~ ruby_branch && $' < "8"
	  cflags.concat cppflags
	  cflags.concat optflags
	  cflags.concat debugflags
	  cflags.concat warnflags
          cppflags = nil
	  optflags = nil
	  debugflags = nil
	  warnflags = nil
	end

        use_rubyspec = false
        if ENV['PATH'].split(/:/).any? {|d| File.executable?("#{d}/git") }
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
          opts2 = opts.dup
          opts2[:section] = "git-mspec"
          b.github("rubyspec", "mspec", "mspec", opts2)
        }
        use_rubyspec &&= b.catch_error {
          opts2 = opts.dup
          opts2[:section] = "git-rubyspec"
          b.github("rubyspec", "rubyspec", "rubyspec", opts2)
        }

        b.mkcd("ruby")
	args = []
	args << "--prefix=#{ruby_build_dir}"
	args << "CFLAGS=#{cflags.join(' ')}" if cflags && !cflags.empty?
	args << "CPPFLAGS=#{cppflags.join(' ')}" if cppflags && !cppflags.empty?
	args << "optflags=#{optflags.join(' ')}" if optflags
	args << "debugflags=#{debugflags.join(' ')}" if debugflags
	args << "warnflags=#{warnflags.join(' ')}" if warnflags
	args << "DLDFLAGS=#{dldflags.join(' ')}" unless dldflags.empty?
	args.concat configure_flags
        b.run("#{srcdir}/configure", *args)
        b.make("miniruby", make_options)
        b.catch_error { b.run("./miniruby", "-v", :section=>"miniversion") }
        if File.directory? "#{srcdir}/bootstraptest"
          b.catch_error { b.make("btest", "OPTS=-v -q", :section=>"btest") }
        end
        b.catch_error {
          b.run("./miniruby", "#{srcdir+'sample/test.rb'}", :section=>"test.rb")
          if /^end of test/ !~ b.logfile.get_section('test.rb')
            raise ChkBuild::Build::CommandError.new(0, "test.rb")
          end
        }
        b.catch_error { b.run("./miniruby", '-e', METHOD_LIST_SCRIPT, :section=>"method-list") }
        if %r{trunk} =~ ruby_branch
          b.make("main", make_options)
        end
        b.make(make_options)
        b.catch_error { b.run("./ruby", "-v", :section=>"version") }
        b.make("install-nodoc")
        b.catch_error { b.make("install-doc") }
        if File.file? "#{srcdir}/KNOWNBUGS.rb"
          b.catch_error { b.make("test-knownbug", "OPTS=-v -q") }
        end
        #b.catch_error { b.run("./ruby", "#{srcdir+'test/runner.rb'}", "-v", :section=>"test-all") }
        b.catch_error {
	  b.make("test-all", "TESTS=-v", :section=>"test-all")
	}
        b.catch_error {
	  if /^\d+ tests, \d+ assertions, (\d+) failures, (\d+) errors/ !~ b.logfile.get_section('test-all')
	    ts = Dir.entries("test").sort
	    ts.each {|t|
	      next if %r{\A\.} =~ t
	      s = File.lstat("test/#{t}")
	      if s.directory? || (s.file? && /\Atest_/ =~ t)
		b.catch_error {
		  b.make("test-all", "TESTS=-v #{t}", :section=>"test/#{t}")
		}
	      end
	    }
	  end
	}

        Dir.chdir(ruby_build_dir)
        if use_rubyspec
          b.catch_error {
	    FileUtils.rmtree "rubyspec_temp"
            if %r{branches/ruby_1_8} =~ ruby_branch
              config = Dir.pwd + "/rubyspec/ruby.1.8.mspec"
            else
              config = Dir.pwd + "/rubyspec/ruby.1.9.mspec"
            end
            command = %W[bin/ruby mspec/bin/mspec -V -f s -B #{config} -t bin/ruby]
            command << "rubyspec"
            command << { :section=>"rubyspec" }
            b.run(*command)
          }
          if /^Finished/ !~ b.logfile.get_section('rubyspec')
	    Pathname("rubyspec").children.reject {|f| !f.directory? }.sort.each {|d|
	      d.stable_find {|f|
		Find.prune if %w[.git fixtures nbproject shared tags].include? f.basename.to_s
		next if /_spec\.rb\z/ !~ f.basename.to_s
		s = f.lstat
		next if !s.file?
		b.catch_error {
		  FileUtils.rmtree "rubyspec_temp"
		  if %r{branches/ruby_1_8} =~ ruby_branch
		    config = ruby_build_dir + "rubyspec/ruby.1.8.mspec"
		  else
		    config = ruby_build_dir + "rubyspec/ruby.1.9.mspec"
		  end
		  command = %W[bin/ruby mspec/bin/mspec -V -f s -B #{config} -t bin/ruby]
		  command << f.to_s
		  command << { :section=>f.to_s }
		  b.run(*command)
		}
	      }
	    }
            b.catch_error {
	      FileUtils.rmtree "rubyspec_temp"
              if %r{branches/ruby_1_8} =~ ruby_branch
                config = Dir.pwd + "/rubyspec/ruby.1.8.mspec"
                #command = %W[bin/ruby mspec/bin/mspec -V -f s -B #{config} -t bin/ruby -G critical]
              else
                config = Dir.pwd + "/rubyspec/ruby.1.9.mspec"
                #command = %W[bin/ruby mspec/bin/mspec ci -V -f s -B #{config} -t bin/ruby]
              end
              command = %W[bin/ruby mspec/bin/mspec ci -V -f s -B #{config} -t bin/ruby]
              command << "rubyspec"
              command << { :section=>"rubyspec-ci" }
              b.run(*command)
            }
          end
        end
      }

      t.add_title_hook("configure") {|title, log|
        if /^checking target system type\.\.\. (\S+)$/ =~ log
          title.update_title(:version, "#{title.suffixed_name} [#{$1}]")
        end
      }

      t.add_title_hook("miniversion") {|title, log|
        if /^ruby [0-9].*$/ =~ log
          ver = $&
          ss = title.suffixed_name.split(/-/)[1..-1].reject {|s| /\A(trunk|1\.8)\z/ =~ s }
          ver << " [#{ss.join(',')}]" if !ss.empty?
          title.update_title(:version, ver)
        end
      }

      t.add_title_hook("version") {|title, log|
        if /^ruby [0-9].*$/ =~ log
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

      t.add_failure_hook("test-knownbug") {|log|
        if /^FAIL (\d+)\/\d+ tests failed/ =~ log
          "#{$1}KB"
        elsif /^\d+ tests, \d+ assertions, (\d+) failures, (\d+) errors$/ =~ log
          failures = $1.to_i
          errors = $2.to_i
          if failures != 0 || errors != 0
            "KB#{failures}F#{errors}E"
          end
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
        elsif /^\d+ tests, \d+ assertions, (\d+) failures, (\d+) errors, (\d+) skips$/ =~ log
          failures = $1.to_i
          errors = $2.to_i
          skips = $3.to_i
          if failures != 0 || errors != 0 || skips != 0
	    if skips == 0
	      "#{failures}F#{errors}E"
	    else
	      "#{failures}F#{errors}E#{skips}S"
	    end
          end
        end
      }

      t.add_failure_hook("rubyspec") {|log|
        if /^\d+ files?, \d+ examples?, \d+ expectations?, (\d+) failures?, (\d+) errors?$/ =~ log
          failures = $1.to_i
          errors = $2.to_i
          if failures != 0 || errors != 0
            "rubyspec:#{failures}F#{errors}E"
          end
        end
      }

      t.add_title_hook(nil) {|title, log|
        mark = ''
        numbugs = count_prefix(/\[BUG\]/i, log) and mark << " #{numbugs}[BUG]"
        numsegv = count_prefix(
          /segmentation fault|signal segv/i,
          log.sub(/combination may cause frequent hang or segmentation fault|hangs or segmentation faults/, '')) and # skip tk message.
          mark << " #{numsegv}[SEGV]"
        numsigbus = count_prefix(/signal SIGBUS/i, log) and mark << " #{numsigbus}[SIGBUS]"
        numsigill = count_prefix(/signal SIGILL/i, log) and mark << " #{numsigill}[SIGILL]"
        numsigabrt = count_prefix(/signal SIGABRT/i, log) and mark << " #{numsigabrt}[SIGABRT]"
        numfatal = count_prefix(/\[FATAL\]/i, log) and mark << " #{numfatal}[FATAL]" 
        mark.sub!(/\A /, '')
        title.update_title(:mark, mark)
      }

      # ruby 1.9.2dev (2009-12-07 trunk 26037) [i686-linux]
      # ruby 1.9.1p376 (2009-12-07 revision 26040) [i686-linux]
      t.add_diff_preprocess_gsub(/^ruby [0-9.a-z]+ \(.*\) \[.*\]$/) {|match|
        "ruby <version>"
      }

      # delete trailing spaces.
      t.add_diff_preprocess_gsub(/[ \t]*$/) {|match|
        ""
      }

      # svn info prints the last revision in the whole repository
      # which can be different from the last changed revision.
      # Revision: 26147
      t.add_diff_preprocess_gsub(/^Revision: \d+/) {|match|
        "Revision: <rev>"
      }

      # test_exception.rb #1 test_exception.rb:1
      t.add_diff_preprocess_gsub(/\#\d+ test_/) {|match|
        "#<n> test_"
      }

      # test/unit:
      #  28) Error:
      #  33) Failure:
      # rubyspec:
      # 61)
      t.add_diff_preprocess_gsub(/^ *\d+\)( Error:| Failure:|$)/) {|match|
        " <n>) #{match[1]}"
      }

      # rubyspec
      # -- reports aborting on a killed thread (FAILED - 9)
      # -- flattens self (ERROR - 21)
      t.add_diff_preprocess_gsub(/\((FAILED|ERROR) - \d+\)$/) {|match|
        "(#{match[1]} - <n>)"
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
        match[0].sub(/[0-9a-f]+\z/) { '<address>' }
      }

      # #<#<Class:0xXXXXXXX>:0x0e87dd00
      # NoMethodError: undefined method `join' for #<#<Class:0x<address>>::Enum:0x00000000d76e98 @elements=[]>
      # order sensitive.  this should be applied after the above.
      t.add_diff_preprocess_gsub(%r{(\#<\#<Class:0x<address>>(?:::[A-Z][A-Za-z0-9_]*)*:0x)([0-9a-f]+)}o) {|match|
        match[1] + '<address>'
      }

      # #<BigDecimal:403070d8,
      t.add_diff_preprocess_gsub(%r{\#<BigDecimal:[0-9a-f]+}) {|match|
        match[0].sub(/[0-9a-f]+\z/) { '<address>' }
      }

      # but got ThreadError (uncaught throw `blah' in thread 0x23f0660)
      t.add_diff_preprocess_gsub(%r{thread 0x[0-9a-f]+}o) {|match|
        match[0].sub(/[0-9a-f]+\z/) { '<address>' }
      }

      # XSD::ValueSpaceError: {http://www.w3.org/2001/XMLSchema}dateTime: cannot accept '2007-02-01T23:44:2682967.846399999994901+09:00'.
      t.add_diff_preprocess_gsub(%r{\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\d+\.\d+}o) {|match|
        s = match[0]
        chars = %w[Y M D h m s s]
        s.gsub!(/\d+/) { "<#{chars.shift}>" }
        s
      }

      # mkdir -p /home/akr/chkbuild/tmp/build/ruby-trunk/<buildtime>/tmp/fileutils.rb.23661/tmpdir/dir/
      t.add_diff_preprocess_gsub(%r{/tmp/fileutils.rb.\d+/tmpdir/}o) {|match|
        '/tmp/fileutils.rb.<n>/tmpdir/'
      }

      # connect to #<Addrinfo: [::1]:54046 TCP>.
      t.add_diff_preprocess_gsub(%r{\#<Addrinfo: \[::1\]:\d+}o) {|match|
        '#<Addrinfo: [::1]:<port>'
      }

      t.add_diff_preprocess_gsub(/^Elapsed: [0-9.]+s/) {|match|
        "Elapsed: <t>s"
      }

      # test/unit:
      # Finished in 139.785699 seconds.
      # rubyspec:
      # Finished in 31.648244 seconds
      t.add_diff_preprocess_gsub(/^Finished in [0-9.]+ seconds/) {|match|
        "Finished in <t> seconds"
      }

      # /tmp/test_rubygems_18634
      t.add_diff_preprocess_gsub(%r{/tmp/test_rubygems_\d+}o) {|match|
        '/tmp/test_rubygems_<pid>'
      }

      # <buildtime>/mspec/lib/mspec/mocks/mock.rb:128:in `__ms_70044980_respond_to?__'
      t.add_diff_preprocess_gsub(%r{__ms_-?\d+_}) {|match|
	'__ms_<object_id>_'
      }

      # miniunit:
      # Complex_Test#test_parse: 0.01 s: .
      t.add_diff_preprocess_gsub(%r{\d+\.\d\d s: }) {|match|
	'<elapsed> s: '
      }

      # Errno::ENOENT: No such file or directory - /home/akr/chkbuild/tmp/build/ruby-trunk/<buildtime>/tmp/generate_test_12905.csv
      t.add_diff_preprocess_gsub(%r{generate_test_\d+.csv}) {|match|
	'generate_test_<digits>.csv'
      }

      # ruby exit stauts is not success: #<Process::Status: pid 7502 exit 1>
      t.add_diff_preprocess_gsub(/\#<Process::Status: pid \d+ /) {|match|
        '#<Process::Status: pid <pid> '
      }

      # MinitestSpec#test_needs_to_verify_nil: <elapsed> s: .
      # RUNIT::TestAssert#test_assert_send: .
      t.add_diff_preprocess_sort(/\A[A-Z][A-Za-z0-9_]+(::[A-Z][A-Za-z0-9_]+)*\#/)

      # - returns self as a symbol literal for :$*
      t.add_diff_preprocess_sort(/\A- returns self as a symbol literal for :/)

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
