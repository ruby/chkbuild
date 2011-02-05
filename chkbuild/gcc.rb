# chkbuild/gcc.rb - gcc build module
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

require 'chkbuild'

module ChkBuild
  module GCC
    module_function
    def def_target(*args)
      gcc = ChkBuild.def_target("gcc",
        *args) {|b, *suffixes|
        gcc_prefix = b.build_dir

        gcc_branch = nil
        odcctools_dir = nil
        suffixes.each {|s|
          case s
          when "trunk" then gcc_branch = "trunk"
          when "4.2" then gcc_branch = "branches/gcc-4_2-branch"
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
        configure_args = %w[--enable-languages=c]
        if odcctools_dir
          configure_args.concat %W[--disable-checking --with-as=#{odcctools_dir}/bin/as --with-ld=#{odcctools_dir}/bin/ld]
        else
          configure_args.concat %W[--disable-shared --disable-multilib]
        end
        b.run("../../gcc/configure", "--prefix=#{gcc_prefix}", *configure_args)
        b.make("bootstrap", "install", :timeout=>'5h')
        b.run("#{gcc_prefix}/bin/gcc", '-v', :section=>'version')
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

      gcc.add_diff_preprocess_gsub(%r{^/tmp/cc[A-Za-z0-9]+\.s:}) {
        '/tmp/cc<tmpnam>.s:'
      }

      gcc
    end
  end
end
