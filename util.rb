# util.rb - utilities
#
# Copyright (C) 2006,2007,2009,2010 Tanaka Akira  <akr@fsij.org>
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
require "find"
require "pathname"
require "rbconfig"
require "stringio"

require "erb"
include ERB::Util

def tp(obj)
  open("/dev/tty", "w") {|f| f.puts obj.inspect }
end

def tpp(obj)
  require 'pp'
  open("/dev/tty", "w") {|f| PP.pp(obj, f) }
end

def ha(str)
  '"' + h(str) + '"'
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

class String
  def lastline
    if pos = rindex(?\n)
      self[(pos+1)..-1]
    else
      self
    end
  end
end

unless File.respond_to? :identical?
  def File.identical?(filename1, filename2)
    test(?-, filename1, filename2)
  end
end

unless STDIN.respond_to? :close_on_exec?
  class IO
    def close_on_exec?
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
end

unless RbConfig.respond_to? :ruby
  def RbConfig.ruby
    File.join(
      RbConfig::CONFIG["bindir"],
      RbConfig::CONFIG["ruby_install_name"] + RbConfig::CONFIG["EXEEXT"]
    )
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

  def atomic_make_compressed_file(filename, content)
    str = ""
    strio = StringIO.new(str)
    Zlib::GzipWriter.wrap(strio) {|z|
      z << content
    }
    atomic_make_file(filename, str)
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

  def format_elapsed_time(seconds)
    res = "#{seconds}s"
    m, s = seconds.divmod(60)
    h, m = m.divmod(60)
    if h != 0
      res << " = #{h}h #{m}m #{s}s"
    elsif m != 0
      res << " = #{m}m #{s}s"
    end
    res
  end
end

module Find
  def stable_find(*paths) # :yield: path
    block_given? or return enum_for(__method__, *paths)

    paths.collect!{|d| raise Errno::ENOENT unless File.exist?(d); d.dup}
    while file = paths.shift
      catch(:prune) do
        yield file.dup.taint
	begin
	  s = File.lstat(file)
        rescue Errno::ENOENT
	  next
        end
        begin
          if s.directory? then
	    fs = Dir.entries(file)
	    fs.sort!
	    fs.reverse!
	    for f in fs
	      next if f == "." or f == ".."
	      if File::ALT_SEPARATOR and file =~ /^(?:[\/\\]|[A-Za-z]:[\/\\]?)$/ then
		f = file + f
	      elsif file == "/" then
		f = "/" + f
	      else
		f = File.join(file, f)
	      end
	      paths.unshift f.untaint
	    end
          end
        rescue Errno::ENOENT, Errno::EACCES
        end
      end
    end
  end
  module_function :stable_find
end

class Pathname    # * Find *
  def stable_find(&block) # :yield: pathname
    if @path == '.'
      Find.stable_find(@path) {|f| yield self.class.new(f.sub(%r{\A\./}, '')) }
    else
      Find.stable_find(@path) {|f| yield self.class.new(f) }
    end
  end
end

