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
