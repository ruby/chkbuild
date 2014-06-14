# util.rb - utilities
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

if "".respond_to? :encode
  def h(str)
    str.encode("US-ASCII", Encoding.find("locale"), :invalid=>:replace, :undef=>:replace, :xml=>:text)
  end
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

  if !"".respond_to?(:start_with?)
    def start_with?(arg, *rest)
      [arg, *rest].any? {|prefix|
        prefix.length <= self.length && prefix == self[0, prefix.length]
      }
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

  def mkcd(dir, &b)
    FileUtils.mkpath dir
    Dir.chdir(dir, &b)
  end

  def search_command(c, path=ENV['PATH'])
    path.split(/:/).each {|d|
      f = File.join(d, c)
      if File.file?(f) && File.executable?(f)
        return f
      end
    }
    nil
  end

  def resource_unlimit(resource)
    if Symbol === resource
      begin
        resource = Process.const_get(resource)
      rescue NameError
        return
      end
    end
    _cur_limit, max_limit = Process.getrlimit(resource)
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
    _cur_limit, max_limit = Process.getrlimit(resource)
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

  def atomic_make_file(filename)
    tmp = nil
    i = 0
    begin
      tmp = "#{filename}.tmp#{i}"
      f = File.open(tmp, File::WRONLY|File::CREAT|File::TRUNC|File::EXCL)
    rescue Errno::EEXIST
      i += 1
      retry
    end
    yield f
    f.close
    File.rename tmp, filename
  end

  def atomic_make_compressed_file(filename)
    atomic_make_file(filename) {|f|
      Zlib::GzipWriter.wrap(f) {|z|
        yield z
        z.finish
      }
    }
  end

  def compress_file(src, dst)
    Zlib::GzipWriter.wrap(open(dst, "w")) {|z|
      open(src) {|f|
        FileUtils.copy_stream(f, z)
      }
    }
  end

  def with_stdouterr(io)
    sync_stdout = STDOUT.sync
    save_stdout = STDOUT.dup
    save_stderr = STDERR.dup
    STDOUT.reopen(io)
    STDERR.reopen(io)
    begin
      yield
    ensure
      STDOUT.reopen(save_stdout)
      STDERR.reopen(save_stderr)
      STDOUT.sync = sync_stdout
      STDERR.sync = true
    end
  end

  def with_tempfile(content) # :yield: tempfile
    t = Tempfile.new("chkbuild")
    t << content
    t.sync
    yield t
  end

  def with_templog(dir, basename)
    n = 1
    begin
      name = "#{dir}/#{basename}#{n}"
      f = File.open(name, File::RDWR|File::CREAT|File::EXCL)
    rescue Errno::EEXIST
      n += 1
      retry
    end
    begin
      yield name, f
    ensure
      f.close
    end
  end

  def simple_hostname
    Socket.gethostname.sub(/\..*/, '')
  end

  def format_elapsed_time(seconds)
    res = "%.1fs" % seconds
    m, s = seconds.divmod(60)
    h, m = m.divmod(60)
    if h != 0
      res << " = %dh %dm %.1fs" % [h, m, s]
    elsif m != 0
      res << " = %dm %.1fs" % [m, s]
    end
    res
  end

  def merge_opts(opts_list)
    h = {}
    max = Hash.new(0)
    opts_list.each {|opts|
      opts.each {|k, v|
        if /_\?\z/ =~ k.to_s
	  base = $`
	  n = (max[base] += 1)
	  k = "#{base}_#{n}".intern
	end
	if /_(\d+)\z/ =~ k.to_s
	  base = $`
	  max[base] = $1.to_i
	end
        if !h.include?(k)
	  h[k] = v
	end
      }
    }
    h
  end

  def opts2allsuffixes(opts)
    opts2aryparam(opts, :suffix).flatten
  end

  def opts2funsuffixes(opts)
    opts2allsuffixes(opts).reject {|s| /\A-/ =~ s }
  end

  def numstrkey(str)
    k = []
    str.scan(/(\d+)|\D+/) {
      if $1
	k << [0, $1.to_i, $&]
      else
	k << [1, $&]
      end
    }
    k
  end

  def numstrsort(ary)
    ary.sort_by {|s| Util.numstrkey(s) }
  end

  def opts2aryparam(opts, name)
    template_list = opts.fetch(name, [])
    return [template_list] unless Array === template_list
    re = /\A#{Regexp.escape name.to_s}_/
    pairs = []
    opts.each {|k, v|
      if re =~ k.to_s
        pairs << [$', v]
      end
    }
    result = []
    template_list.each {|e|
      if Symbol === e
	e = e.to_s
        if /_\?\z/ =~ e
	  base = $`
	  re2 = /\A#{Regexp.escape base.to_s}_/
	  ps, pairs = pairs.partition {|k, v| re2 =~ k }
	else
	  ps, pairs = pairs.partition {|k, v| e == k }
	end
	ps = ps.sort_by {|k, v| Util.numstrkey(k) }
	ps.each {|k, v|
	  v = [v] unless Array === v
	  result.concat v
	}
      else
        result << e
      end
    }
    pairs = pairs.sort_by {|k, v| Util.numstrkey(k) }
    pairs.each {|k, v|
      v = [v] unless Array === v
      result.concat v
    }
    result
  end

  def opts2nullablearyparam(opts, name)
    return opts2aryparam(opts, name) if opts.has_key?(name)
    re = /\A#{Regexp.escape name.to_s}_/
    return opts2aryparam(opts, name) if opts.any? {|k, v| re =~ k.to_s }
    return nil
  end

  def opts2hashparam(opts, name)
    h = {}
    re = /\A#{Regexp.escape name.to_s}_/
    opts.each {|k, v|
      if re =~ k.to_s
        h[$'] = v
      end
    }
    h
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

