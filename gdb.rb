# gdb.rb - gdb invocation library
#
# Copyright (C) 2005-2012 Tanaka Akira  <akr@fsij.org>
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

require 'find'
require 'tempfile'

require 'escape'

module GDB
  module_function

  def check_core(dir)
    binaries = {}
    core_info = []
    Find.find(dir.to_s) {|f|
      stat = File.lstat(f)
      basename = File.basename(f)
      binaries[basename] = f if stat.file? && stat.executable?
      next if /\bcore\b/ !~ basename
      next if /\.chkbuild\.\d+\z/ =~ basename
      guess = `file #{f} 2>&1`
      next if /\bcore\b.*from '(.*?)'/ !~ guess.sub(/\A.*?:/, '')
      binary = $1
      next if /\bconftest\b/ =~ binary
      core_info << [f, binary]
    }
    gdb_command = nil
    core_info.each {|core_path, binary|
      next unless binary_path = binaries[binary]
      core_path = rename_core(core_path)
      unless gdb_command
        gdb_command = Tempfile.new("gdb-bt")
        gdb_command.puts "bt 1000"
        gdb_command.close
      end
      puts
      puts "binary: #{binary_path}"
      puts "core: #{core_path}"
      command = %W[gdb -batch -n -x #{gdb_command.path} #{binary_path} #{core_path}]
      gdb_output = `#{Escape.shell_command command}`
      puts gdb_output
      puts "gdb status: #{$?}"
    }
  end

  def rename_core(core_path)
    suffix = ".chkbuild."
    n = 1
    while File.exist?(new_path = "#{core_path}#{suffix}#{n}")
      n += 1
    end
    File.rename(core_path, new_path)
    new_path
  end
end
