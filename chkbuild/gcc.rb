#!/usr/bin/env ruby

require 'chkbuild'

module ChkBuild
  module GCC
    module_function
    def def_target(*args)
      gcc = ChkBuild.def_target("gcc",
        *args) {|b, *suffixes|
        gcc_dir = b.build_dir

        gcc_branch = nil
        odcctools_dir = nil
        suffixes.each {|s|
          case s
          when "trunk" then gcc_branch = "trunk"
          when "4.1" then gcc_branch = "branches/gcc-4_1-branch"
          when "4.0" then gcc_branch = "branches/gcc-4_0-branch"
          when /\Aodcctools_dir=/
            odcctools_dir = $'
          else
            raise "unexpected suffix: #{s.inspect}"
          end
        }

        Dir.chdir("..") {
          if odcctools_dir
            File.unlink("gcc/gcc/config/darwin.h") rescue nil
          end
          b.svn("svn://gcc.gnu.org/svn/gcc", gcc_branch, 'gcc',
            :viewvc=>"http://gcc.gnu.org/viewcvs")
          if odcctools_dir
            b.run("perl", "-pi", "-e", "s,/usr/bin/libtool,/Users/akr/bin/libtool,;", "gcc/gcc/config/darwin.h")
          end
        }
        b.mkcd("objdir")
        configure_flags = %w[--enable-languages=c --disable-shared --disable-multilib]
        if odcctools_dir
          configure_flags.concat %W[--disable-checking --with-as=#{odcctools_dir}/bin/as --with-ld=#{odcctools_dir}/bin/ld]
        end
        b.run("../../gcc/configure", "--prefix=#{gcc_dir}", *configure_flags)
        b.make("bootstrap", "install", :timeout=>'5h')
        b.run("#{gcc_dir}/bin/gcc", '-v', :section=>'version')
      }

      gcc.add_title_hook('version') {|title, log|
        if /^gcc version (.*)$/ =~ log
          title.update_title(:version, "gcc #{$1}")
        end
      }

      gcc.add_diff_preprocess_gsub(
        /^(\ \ transformation:\ [0-9.]+,\ building\ DFA:\ [0-9.]+
          |\ \ transformation:\ [0-9.]+,\ building\ NDFA:\ [0-9.]+,\ NDFA\ ->\ DFA:\ [0-9.]+
          |\ \ DFA\ minimization:\ [0-9.]+,\ making\ insn\ equivalence:\ [0-9.]+
          |\ all\ automaton\ generation:\ [0-9.]+,\ output:\ [0-9.]+
          )$/x) {|match|
        match[0].gsub(/[0-9.]+/, '<t>')
      }

      gcc
    end
  end
end
