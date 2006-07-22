require 'fileutils'
require 'socket'
require "uri"
require "etc"
require "digest/sha2"
require "fcntl"
require "tempfile"

def tp(obj)
  open("/dev/tty", "w") {|f| f.puts obj.inspect }
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

class Build
  def Build.mkcd(*args, &b) $Build.mkcd(*args, &b) end
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

  def identical_file?(f1, f2)
    s1 = File.stat(f1)
    s2 = File.stat(f2)
    s1.dev == s2.dev && s1.ino == s2.ino
  end

  def cvs_revisions
    h = {}
    Dir.glob("**/CVS").each {|cvs_dir|
      cvsroot = IO.read("#{cvs_dir}/Root").chomp
      repository = IO.read("#{cvs_dir}/Repository").chomp
      ds = cvs_dir.split(%r{/})[0...-1]
      IO.foreach("#{cvs_dir}/Entries") {|line|
        h[[ds, $1]] = [cvsroot, repository, $2] if %r{^/([^/]+)/([^/]*)/} =~ line
      }
    }
    h
  end

  def cvs_print_revisions(h1, h2, viewcvs=nil)
    if h1
      changes = 'changes:'
      (h1.keys | h2.keys).sort.each {|k|
        f = k.flatten.join('/')
        cvsroot1, repository1, r1 = h1[k] || [nil, nil, 'none']
        cvsroot2, repository2, r2 = h2[k] || [nil, nil, 'none']
        if r1 != r2
          if changes
            puts changes
            changes = nil
          end
          line = "#{f}\t#{r1} -> #{r2}"
          if viewcvs
            repository = repository1 || repository2
            uri = URI.parse(viewcvs)
            path = uri.path.dup
            path << "/" << repository if repository != '.'
            path << "/#{k[1]}"
            uri.path = path
            query = (uri.query || '').split(/[;&]/)
            if r1 == 'none'
              query << "rev=#{r2}"
            elsif r2 == 'none'
              query << "rev=#{r1}"
            else
              query << "r1=#{r1}" << "r2=#{r2}"
            end
            uri.query = query.join(';')
            line << "\t" << uri.to_s
          end
          puts line
        end
      }
    end
    puts 'revisions:'
    h2.keys.sort.each {|k|
      f = k.flatten.join('/')
      cvsroot2, repository2, r2 = h2[k] || [nil, nil, 'none']
      digest = sha256_digest_file(f)
      puts "#{f}\t#{r2}\t#{digest}"
    }
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

  def Build.cvs(*args, &b) $Build.cvs(*args, &b) end
  def cvs(cvsroot, mod, branch, opts={})
    opts = opts.dup
    opts[:section] ||= 'cvs'
    working_dir = opts.fetch(:working_dir, mod)
    if !File.exist? "#{ENV['HOME']}/.cvspass"
      opts['ENV:CVS_PASSFILE'] = '/dev/null' # avoid warning
    end
    if File.directory?(working_dir)
      Dir.chdir(working_dir) {
        h1 = cvs_revisions
        $Build.run("cvs", "-f", "-z3", "-Q", "update", "-kb", "-dP", opts)
        h2 = cvs_revisions
        cvs_print_revisions(h1, h2, opts[:viewcvs]||opts[:cvsweb])
      }
    else
      h1 = nil
      if identical_file?(@dir, '.') &&
         !(ts = build_time_sequence - [@start_time]).empty? &&
         File.directory?(old_working_dir = "#{@target_dir}/#{ts.last}/#{working_dir}")
        Dir.chdir(old_working_dir) {
          h1 = cvs_revisions
        }
      end
      if branch
        $Build.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-kb", "-d", working_dir, "-Pr", branch, mod, opts)
      else
        $Build.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-kb", "-d", working_dir, "-P", mod, opts)
      end
      Dir.chdir(working_dir) {
        h2 = cvs_revisions
        cvs_print_revisions(h1, h2, opts[:viewcvs]||opts[:cvsweb])
      }
    end
  end

  def Build.svn(*args, &b) $Build.svn(*args, &b) end
  def svn(url, working_dir, opts={})
    opts = opts.dup
    opts[:section] ||= 'svn'
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.svn")
      Dir.chdir(working_dir) {
        $Build.run "svn", "cleanup", opts
        opts[:section] = nil
        $Build.run "svn", "update", opts
      }
    else
      if File.exist?(working_dir)
        FileUtils.rm_rf(working_dir)
      end
      $Build.run "svn", "checkout", url, working_dir, opts
    end
  end

  def with_tempfile(content) # :yield: tempfile
    t = Tempfile.new("chkbuild")
    t << content
    t.sync
    yield t
  end

  def Build.gnu_savannah_cvs(*args, &b) $Build.gnu_savannah_cvs(*args, &b) end
  def gnu_savannah_cvs(proj, mod, branch, opts={})
    opts = opts.dup
    opts[:viewcvs] ||= "http://savannah.gnu.org/cgi-bin/viewcvs/#{proj}?diff_format=u"
    $Build.cvs(":pserver:anonymous@cvs.savannah.gnu.org:/sources/#{proj}", mod, branch, opts)
  end

  def Build.make(*args, &b) $Build.make(*args, &b) end
  def make(*targets)
    opts = {}
    opts = targets.pop if Hash === targets.last
    opts = opts.dup
    opts[:alt_commands] = ['make']
    if targets.empty?
      opts[:section] ||= 'make'
      $Build.run("gmake", opts)
    else
      targets.each {|target|
	h = opts.dup
	h[:reason] = target
        h[:section] = target
        $Build.run("gmake", target, h)
      }
    end
  end

  def self.rsync_ssh_upload_target(rsync_target, private_key=nil)
    Build.add_upload_hook {|name|
      Build.do_upload_rsync_ssh(rsync_target, private_key, name)
    }
  end

  def self.do_upload_rsync_ssh(rsync_target, private_key, name)
    if %r{\A(?:([^@:]+)@)([^:]+)::(.*)\z} !~ rsync_target
      raise "invalid rsync target: #{rsync_target.inspect}"
    end
    remote_user = $1 || ENV['USER'] || Etc.getpwuid.name
    remote_host = $2
    remote_path = $3
    local_host = Socket.gethostname
    private_key ||= "#{ENV['HOME']}/.ssh/chkbuild-#{local_host}-#{remote_host}"

    pid = fork {
      ENV.delete 'SSH_AUTH_SOCK'
      exec "rsync", "--delete", "-rte", "ssh -akxi #{private_key}", "#{Build.public_dir}/#{name}", "#{rsync_target}"
    }
    Process.wait pid
  end
end
