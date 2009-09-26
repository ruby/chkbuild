# Copyright (C) 2006,2007,2009 Tanaka Akira  <akr@fsij.org>
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

require 'fileutils'
require 'socket'
require "etc"
require "digest/sha2"
require "fcntl"
require "tempfile"

def tp(obj)
  open("/dev/tty", "w") {|f| f.puts obj.inspect }
end

def tpp(obj)
  require 'pp'
  open("/dev/tty", "w") {|f| PP.pp(obj, f) }
end

module Kernel
  if !nil.respond_to?(:funcall)
    if nil.respond_to?(:fcall) 
      alias funcall fcall
    else
      alias funcall send
    end
  end
end

unless File.respond_to? :identical?
  def File.identical?(filename1, filename2)
    test(?-, filename1, filename2)
  end
end

class IO
  def close_on_exec
    self.fcntl(Fcntl::F_GETFD) & Fcntl::FD_CLOEXEC != 0
  end

  def close_on_exec=(v)
    flags = self.fcntl(Fcntl::F_GETFD)
    if v
      flags |= Fcntl::FD_CLOEXEC
    else
      flags &= ~Fcntl::FD_CLOEXEC
    end
    self.fcntl(Fcntl::F_SETFD, flags)
    v
  end
end

class Tempfile
  def gather_each(arg)
    if Regexp === arg
      regexp = arg
      arg = lambda {|e| regexp =~ e; $& }
    end
    prev_value = prev_elts = nil
    self.each {|e|
      v = arg.call(e)
      if prev_value == nil
        if v == nil
          yield [e]
        else
          prev_value = v
          prev_elts = [e]
        end
      else
        if v == nil
          yield prev_elts
          yield [e]
          prev_value = prev_elts = nil
        elsif prev_value == v
          prev_elts << e
        else
          yield prev_elts
          prev_value = v
          prev_elts = [e]
        end
      end
    }
    if prev_value != nil
      yield prev_elts
    end
  end
end

module Util
  extend Util # similar to module_function but instance methods are public.

  # Util.rproduct(ary1, ary2, ...)
  #
  #  Util.rproduct([1,2],[3,4]) #=> [[1, 3], [2, 3], [1, 4], [2, 4]]
  def rproduct(*args)
    if block_given?
      product_each(*args.reverse) {|vs| yield vs.reverse }
    else
      r = []
      product_each(*args.reverse) {|vs| r << vs.reverse }
      r
    end
  end

  def product(*args)
    if block_given?
      product_each(*args) {|vs| yield vs }
    else
      r = []
      product_each(*args) {|vs| r << vs }
      r
    end
  end

  def product_each(*args)
    if args.empty?
      yield []
    else
      arg, *rest = args
      arg.each {|v|
        product_each(*rest) {|vs|
          yield [v, *vs]
        }
      }
    end
  end

  def mkcd(dir)
    FileUtils.mkpath dir
    Dir.chdir dir
  end

  def resource_unlimit(resource)
    if Symbol === resource
      begin
        resource = Process.const_get(resource)
      rescue NameError
        return
      end
    end
    cur_limit, max_limit = Process.getrlimit(resource)
    Process.setrlimit(resource, max_limit, max_limit)
  end

  def resource_limit(resource, val)
    if Symbol === resource
      begin
        resource = Process.const_get(resource)
      rescue NameError
        return
      end
    end
    cur_limit, max_limit = Process.getrlimit(resource)
    if max_limit < val
      val = max_limit
    end
    Process.setrlimit(resource, val, val)
  end

  def sha256_digest_file(filename)
    d = Digest::SHA256.new
    open(filename) {|f|
      buf = ""
      while f.read(4096, buf)
        d << buf
      end
    }
    "sha256:#{d.hexdigest}"
  end

  def force_link(old, new)
    i = 0
    tmp = new
    begin
      File.link old, tmp
    rescue Errno::EEXIST
      i += 1
      tmp = "#{new}.tmp#{i}"
      retry
    end
    if tmp != new
      File.rename tmp, new
    end
  end

  def atomic_make_file(filename, content)
    tmp = nil
    i = 0
    begin
      tmp = "#{filename}.tmp#{i}"
      f = File.open(tmp, File::WRONLY|File::CREAT|File::TRUNC|File::EXCL)
    rescue Errno::EEXIST
      i += 1
      retry
    end
    f << content
    f.close
    File.rename tmp, filename
  end

  def with_tempfile(content) # :yield: tempfile
    t = Tempfile.new("chkbuild")
    t << content
    t.sync
    yield t
  end

  def simple_hostname
    Socket.gethostname.sub(/\..*/, '')
  end
end
