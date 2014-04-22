# chkbuild/gcc.rb - gcc build module
#
# Copyright (C) 2006-2012 Tanaka Akira  <akr@fsij.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#  3. The name of the author may not be used to endorse or promote
#     products derived from this software without specific prior
#     written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'chkbuild'
require 'open-uri'

module ChkBuild
  module GCC
    URL_GMP = "ftp://gcc.gnu.org/pub/gcc/infrastructure/gmp-4.3.2.tar.bz2"
    URL_MPFR = "ftp://gcc.gnu.org/pub/gcc/infrastructure/mpfr-2.4.2.tar.bz2"
    URL_MPC = "ftp://gcc.gnu.org/pub/gcc/infrastructure/mpc-0.8.1.tar.gz"

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

    def remove_symlink(destination)
      if File.symlink? destination
        File.delete destination
      end
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
      if !File.directory?(d)
	b.run('sh', '-c', c)
	if !File.directory?(d)
	  raise "not exist: #{d.inspect}"
	end
      end
      File.symlink "../#{d}", destination
    end

    def def_target(*args)
      args << { :complete_options => CompleteOptions }
      ChkBuild.def_target("gcc", *args)
    end
  end
end

module ChkBuild::GCC::CompleteOptions
end
def (ChkBuild::GCC::CompleteOptions).call(target_opts)
  hs = []
  suffixes = Util.opts2funsuffixes(target_opts)
  suffixes.each {|s|
    case s
    when "trunk" then
      hs << { :gcc_branch => "trunk", :build_gmp => true, :build_mpfr => true, :build_mpc => true }
    when "4.7" then
      hs << { :gcc_branch => "branches/gcc-4_7-branch", :build_gmp => true, :build_mpfr => true, :build_mpc => true }
    when "4.6" then
      hs << { :gcc_branch => "branches/gcc-4_6-branch", :build_gmp => true, :build_mpfr => true, :build_mpc => true }
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

ChkBuild.define_build_proc('gcc') {|b|
  opts = b.opts

  gcc_prefix = b.build_dir
  abs_objdir = gcc_prefix+'objdir'
  rel_srcdir = (b.target_dir+'gcc').relative_path_from(abs_objdir)

  gcc_branch = opts.fetch(:gcc_branch)


  Dir.chdir(b.target_dir) {
    ChkBuild::GCC.remove_symlink("gcc/gmp")
    ChkBuild::GCC.remove_symlink("gcc/mpfr")
    ChkBuild::GCC.remove_symlink("gcc/mpc")
    b.svn("svn://gcc.gnu.org/svn/gcc", gcc_branch, 'gcc',
      :output_interval_timeout => '30min')
    ChkBuild::GCC.download_lib(b, ChkBuild::GCC::URL_GMP, "gcc/gmp") if opts[:build_gmp]
    ChkBuild::GCC.download_lib(b, ChkBuild::GCC::URL_MPFR, "gcc/mpfr") if opts[:build_mpfr]
    ChkBuild::GCC.download_lib(b, ChkBuild::GCC::URL_MPC, "gcc/mpc") if opts[:build_mpc]
  }
  b.mkcd(abs_objdir) {
    configure_args = %w[--enable-languages=c]
    configure_args.concat %W[--disable-multilib]
    b.run("#{rel_srcdir}/configure", "--prefix=#{gcc_prefix}", *configure_args)
    b.make("bootstrap", "install", :timeout=>'5h')
    b.run("#{gcc_prefix}/bin/gcc", '-v', :section=>'version', "ENV:LC_ALL"=>"C")
  }
}

ChkBuild.define_title_hook('gcc', 'version') {|title, log|
  if /^gcc version (.*)$/ =~ log
    title.update_title(:version, "gcc #{$1}")
  end
}

ChkBuild.define_diff_preprocess_gsub('gcc',
  /^(\ \ transformation:\ [0-9.]+,\ building\ DFA:\ [0-9.]+
    |\ \ transformation:\ [0-9.]+,\ building\ NDFA:\ [0-9.]+,\ NDFA\ ->\ DFA:\ [0-9.]+
    |\ \ DFA\ minimization:\ [0-9.]+,\ making\ insn\ equivalence:\ [0-9.]+
    |\ all\ automaton\ generation:\ [0-9.]+,\ output:\ [0-9.]+
    )$/x) {|match|
  match[0].gsub(/[0-9.]+/, '<t>')
}

ChkBuild.define_diff_preprocess_gsub('gcc', %r{^/tmp/cc[A-Za-z0-9]+\.s:}) {
  '/tmp/cc<tmpnam>.s:'
}

ChkBuild.define_diff_preprocess_gsub('gcc', %r{-DBASEVER="\\"\d+.\d+.\d+\\""}) {
  '-DBASEVER="\"N.N.N\""'
}

ChkBuild.define_diff_preprocess_gsub('gcc', %r{-DDATESTAMP="\\" \d{8}\\""}) {
  '-DDATESTAMP="\" YYYYMMDD\""'
}

ChkBuild.define_diff_preprocess_gsub('gcc', %r{--release="gcc-\d+.\d+.\d+"}) {
  '--release="gcc-N.N.N"'
}

ChkBuild.define_diff_preprocess_gsub('gcc', %r{--date=\d+-\d\d-\d\d}) {
  '--date=YYYY-MM-DD'
}

ChkBuild.define_diff_preprocess_gsub('gcc', %r{^gcc version .*}) {
  'gcc version ...'
}

# segment       = *pchar
# pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
# unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
# pct-encoded   = "%" HEXDIG HEXDIG
# sub-delims    = "!" / "$" / "&" / "'" / "(" / ")"
#               / "*" / "+" / "," / ";" / "="
segment_regexp = '(?:[A-Za-z0-9\-._~!$&\'()*+,;=:@]|%[0-9A-Fa-f][0-9A-Fa-f])*'

ChkBuild.define_file_changes_viewer('svn',
  %r{\Asvn://gcc\.gnu\.org/svn/gcc (#{segment_regexp}(/#{segment_regexp})*)?\z}o) {
  |match, reptype, pat, checkout_line|
  # svn://gcc.gnu.org/svn/gcc
  # http://gcc.gnu.org/viewcvs

  mod = match[1]
  mod = nil if mod && mod.empty?
  ChkBuild::ViewVC.new('http://gcc.gnu.org/viewcvs', false, mod)
}

