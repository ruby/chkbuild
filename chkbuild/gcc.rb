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
require 'open-uri'

module ChkBuild
  module GCC
    URL_GMP = "ftp://gcc.gnu.org/pub/gcc/infrastructure/gmp-4.3.2.tar.bz2"
    URL_MPFR = "ftp://gcc.gnu.org/pub/gcc/infrastructure/mpfr-2.4.2.tar.bz2"
    URL_MPC = "ftp://gcc.gnu.org/pub/gcc/infrastructure/mpc-0.8.1.tar.gz"

    module CompleteOptions
    end
    def CompleteOptions.call(target_opts)
      hs = []
      suffixes = Util.opts2funsuffixes(target_opts)
      suffixes.each {|s|
        case s
	when "trunk" then
	  hs << { :gcc_branch => "trunk", :build_gmp => true, :build_mpfr => true, :build_mpc => true }
	when "4.5" then
	  hs << { :gcc_branch => "branches/gcc-4_5-branch", :build_gmp => true, :build_mpfr => true, :build_mpc => true }
	when "4.4" then
	  hs << { :gcc_branch => "branches/gcc-4_4-branch", :build_gmp => true, :build_mpfr => true }
	when "4.3" then
	  hs << { :gcc_branch => "branches/gcc-4_3-branch", :build_gmp => true, :build_mpfr => true }
	when "4.2" then
	  hs << { :gcc_branch => "branches/gcc-4_2-branch" }
	when "4.1" then
	  hs << { :gcc_branch => "branches/gcc-4_1-branch" }
	when "4.0" then
	  hs << { :gcc_branch => "branches/gcc-4_0-branch" }
        else
          raise "unexpected suffix: #{s.inspect}"
        end
      }

      opts = target_opts.dup
      hs.each {|h|
        h.each {|k, v|
          opts[k] = v if !opts.include?(k)
        }
      }
      opts
    end

    module_function

    def cached_download(b, url, dst)
      return if File.exist?(dst)
      b.network_access {
	URI(url).open {|f|
	  File.open(dst, 'wb') {|f2|
	    while buf = f.read(4096)
	      f2.write buf
	    end
	  }
	}
      }
    end

    def download_lib(b, url, destination)
      return if File.directory? destination
      basename = url[%r{[^/]+\z}]
      cached_download(b, url, basename)
      if /\.tar\.gz\z/ =~ basename
        d = $`
	c = "#{Escape.shell_command(['gzip', '-dc'])} < #{Escape.shell_single_word basename} | tar xf -"
      elsif /\.tar\.bz2\z/ =~ basename
        d = $`
	c = "#{Escape.shell_command(['bzip2', '-dc'])} < #{Escape.shell_single_word basename} | tar xf -"
      else
        raise "unexpected basename: #{basename.inspect}"
      end
      b.run('sh', '-c', c)
      if !File.directory?(d)
        raise "not exist: #{d.inspect}"
      end
      #File.rename d, destination
      File.symlink "../#{d}", destination
    end

    def def_target(*args)
      default_opts = {
        :complete_options => CompleteOptions,
      }
      args.push default_opts
      gcc = ChkBuild.def_target("gcc", *args) {|b|
	opts = b.opts

        gcc_prefix = b.build_dir

        gcc_branch = opts.fetch(:gcc_branch)

        Dir.chdir("..") {
          b.svn("svn://gcc.gnu.org/svn/gcc", gcc_branch, 'gcc',
            :viewvc=>"http://gcc.gnu.org/viewcvs",
	    :output_interval_timeout => '30min')
	  download_lib(b, URL_GMP, "gcc/gmp") if opts[:build_gmp]
	  download_lib(b, URL_MPFR, "gcc/mpfr") if opts[:build_mpfr]
	  download_lib(b, URL_MPC, "gcc/mpc") if opts[:build_mpc]
        }
        b.mkcd("objdir")
        configure_args = %w[--enable-languages=c]
	configure_args.concat %W[--disable-shared --disable-multilib]
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

      gcc.add_diff_preprocess_gsub(%r{-DBASEVER="\\"\d+.\d+.\d+\\""}) {
        '-DBASEVER="\"N.N.N\""'
      }

      gcc.add_diff_preprocess_gsub(%r{-DDATESTAMP="\\" \d{8}\\""}) {
        '-DDATESTAMP="\" YYYYMMDD\""'
      }

      gcc.add_diff_preprocess_gsub(%r{--release="gcc-\d+.\d+.\d+"}) {
        '--release="gcc-N.N.N"'
      }

      gcc.add_diff_preprocess_gsub(%r{--date=\d+-\d\d-\d\d}) {
        '--date=YYYY-MM-DD'
      }

      gcc.add_diff_preprocess_gsub(%r{^gcc version .*}) {
        'gcc version ...'
      }

      gcc
    end
  end
end
