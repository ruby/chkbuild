# chkbuild.rb - chkbuild library entry file
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

Encoding.default_external = "ASCII-8BIT" if defined?(Encoding.default_external = nil)

require 'cgi'
require 'digest/sha2'
require 'erb'
require 'etc'
require 'fcntl'
require 'fileutils'
require 'find'
require 'open-uri'
require 'optparse'
require 'pathname'
require 'pp'
require 'rbconfig'
require 'rss'
require 'socket'
require 'stringio'
require 'tempfile'
require 'time'
require 'uri'
require 'zlib'

require 'util'
require 'escape'
require 'gdb'
require 'lchg'
require 'erbio'
require 'timeoutcom'

require 'chkbuild/main'
require 'chkbuild/config'
require 'chkbuild/lock'
require 'chkbuild/hook'
require 'chkbuild/logfile'
require 'chkbuild/options'
require 'chkbuild/title'
require 'chkbuild/upload'

require 'chkbuild/target'
require 'chkbuild/build'
require 'chkbuild/ibuild'
require 'chkbuild/iformat'

require 'chkbuild/cvs'
require 'chkbuild/svn'
require 'chkbuild/git'
require 'chkbuild/viewvc'

require 'chkbuild/ruby'
require 'chkbuild/gcc'
require 'chkbuild/openssl'
require 'chkbuild/zlib'
