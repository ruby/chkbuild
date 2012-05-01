# chkbuild/openssl.rb - openssl build module
#
# Copyright (C) 2012 Tanaka Akira  <akr@fsij.org>
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
  module OpenSSL
    module_function
    def def_target(*args)
      args << { :complete_options => CompleteOptions }
      ChkBuild.def_target('openssl', *args)
    end
  end
end

module ChkBuild::OpenSSL::CompleteOptions
end

def (ChkBuild::OpenSSL::CompleteOptions).merge_dependencies(opts, dep_dirs)
  opts = opts.dup
  dep_dirs.each {|s|
    case s
    when /\Azlib=/
      opts.update({
        :configure_args_zlib_lib => "--with-zlib-lib=#{$'}/lib",
        :configure_args_zlib_include => "--with-zlib-include=#{$'}/include",
        :"make_options_ENV:LD_RUN_PATH" => "#{$'}/lib"
      })
    end
  }
  opts
end

ChkBuild.define_build_proc('openssl') {|b|
  make_options = Util.opts2hashparam(b.opts, :make_options)
  cvs_shared_dir = ChkBuild.build_top + 'cvs-repos'
  FileUtils.mkdir_p(cvs_shared_dir)
  b.run('rsync', '-rztpv', '--delete',
        'rsync://dev.openssl.org/openssl-cvs/',
        "#{cvs_shared_dir}/openssl-cvs")
  b.cvs("#{cvs_shared_dir}/openssl-cvs",
        'openssl',
        b.opts[:openssl_branch],
        b.opts)
  bdir = b.build_dir
  configure_args = [
    "--prefix=#{bdir}",
    "--openssldir=#{bdir}/ssl",
    'shared',
    'zlib'
  ]
  configure_args.concat Util.opts2aryparam(b.opts, :configure_args)
  Dir.chdir('openssl') {
    b.run('./config', *configure_args)
    b.make(make_options)
    b.make('test', make_options)
    b.make('install', make_options)
    b.catch_error {
      b.run("#{bdir}/bin/openssl", 'version', '-a', :section=>"version")
    }
    b.catch_error {
      b.run("cat", "#{bdir}/lib/pkgconfig/openssl.pc", :section=>"pkgconfig")
    }
  }
}

ChkBuild.define_title_hook('openssl', 'version') {|title, log|
  # OpenSSL 0.9.8x-dev xx XXX xxxx
  case log
  when /^(OpenSSL .*)$/
    ver = $1
    ver.sub!(/ xx XXX xxxx\z/, '')
    title.update_title(:version, ver)
  end
}

