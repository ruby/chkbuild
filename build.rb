require 'fileutils'
require 'time'
require 'socket'
require 'zlib'
require "erb"
include ERB::Util

require 'escape'
require 'timeoutcom'
require 'dynamic'
require 'gdb'

def tp(obj)
  open("/dev/tty", "w") {|f| f.puts obj.inspect }
end

module Build
  module_function

  def build_dir
    "#{TOP_DIRECTORY}/tmp/build"
  end

  def public_dir
    "#{TOP_DIRECTORY}/tmp/public_html"
  end

  def mkcd(dir)
    FileUtils.mkpath dir
    Dir.chdir dir
  end

  def remove_old_build(current, num)
    dirs = Dir.entries("..")
    dirs.reject! {|d| /\A\d{8}T\d{6}/ !~ d } # year 10000 problem
    dirs.sort!
    dirs.delete current
    return if dirs.length <= num
    dirs[-num..-1] = []
    dirs.each {|d|
      FileUtils.rmtree "../#{d}"
    }
  end

  def careful_link(old, new)
    tmp = nil
    i = 0
    loop {
      i += 1
      tmp = "#{new}.tmp#{i}"
      break unless File.exist? tmp
    }
    File.link old, tmp
    File.rename tmp, new
  end

  def update_title(key, val)
    h = Dynamic.ref(:title)
    h[key] = val
  end

  def all_log
    File.read(Dynamic.ref(:log_filename))
  end

  def count_warns
    num_warns = all_log.scan(/warn/i).length
    Dynamic.ref(:title)[:warn] = "#{num_warns}W" if 0 < num_warns
  end

  def make_title
    if !Dynamic.ref(:title)[:status]
      if $!
        if CommandError === $!
          Build.update_title(:status, "failed(#{$!.reason})")
        else
          Build.update_title(:status, "failed(#{$!.class}:#{$!.message})")
        end
      else
        Build.update_title(:status, "failed")
      end
    end
    title_hash = Dynamic.ref(:title)
    Dynamic.ref(:title_order).map {|key| title_hash[key] }.join(' ').gsub(/\s+/, ' ').strip
  end

  def add_finish_hook(&block)
    Dynamic.ref(:finish_hook) << block
  end

  def update_summary(name, public, start_time_str, title)
    open("#{public}/summary.txt", "a") {|f| f.puts "#{start_time_str} #{title}" }
    open("#{public}/summary.html", "a") {|f|
      if f.stat.size == 0
        f.puts "<title>#{h name} build summary</title>"
        f.puts "<h1>#{h name} build summary</h1>"
        f.puts "<p><a href=\"../\">autobuild</a></p>"
      end
      f.puts "<a href=\"log/#{start_time_str}.txt.gz\">#{h start_time_str}</a> #{h title}<br>"
    }
  end

  def compress_file(src, dst)
    Zlib::GzipWriter.wrap(open(dst, "w")) {|g| g << File.read(src) }
  end

  def combination(*args_list)
    opts = {}
    opts = args_list.pop if Hash === args_list.last
    args_list.each {|name, *args|
      pid = fork {
        LOCK.puts name
        Dynamic.bind(:title => {},
                     :title_order => nil,
                     :log_filename => nil,
                     :finish_hook => []) {
          Dynamic.ref(:title)[:version] = name
          Dynamic.ref(:title)[:hostname] = "(#{Socket.gethostname})"
          Dynamic.assign(:title_order, [:status, :warn, :mark, :version, :hostname])
          Build.add_finish_hook { count_warns }
          begin
            begin
              start_time = Time.now
              start_time_str = start_time.strftime("%Y%m%dT%H%M%S")
              dir = "#{Build.build_dir}/#{name}/#{start_time_str}"
              raise "already exist: #{dir}" if File.exist? dir
              Build.add_finish_hook { GDB.check_core(dir) }
              Build.mkcd dir
              STDOUT.reopen((log_filename = "#{dir}/log"), "w")
              STDERR.reopen(STDOUT)
              STDOUT.sync = true
              STDERR.sync = true
              Dynamic.assign(:log_filename, log_filename)
              puts start_time.iso8601
              system("uname -a")
              remove_old_build(start_time, opts.fetch(:old, 3))
              FileUtils.mkpath(public = "#{Build.public_dir}/#{name}")
              FileUtils.mkpath(public_log = "#{public}/log")
              careful_link "log", (latest_new = "#{public}/latest.new")
              yield dir, name, *args
              Dynamic.ref(:title)[:status] ||= 'success'
            ensure
              Dynamic.ref(:finish_hook).reverse_each {|block|
                begin
                  block.call
                rescue Exception
                end
              }
              puts Time.now.iso8601
              careful_link latest_new, "#{public}/latest.txt"
              title = make_title
              update_summary(name, public, start_time_str, title)
              compress_file(log_filename, "#{public_log}/#{start_time_str}.txt.gz")
            end
          rescue CommandError
          end
        }
      }
      Process.wait pid
    }
  end

  class CommandError < StandardError
    def initialize(status, reason, message=reason)
      super message
      @reason = reason
      @status = status
    end

    attr_accessor :reason
  end
  def run(command, *args)
    opts = {}
    opts = args.pop if Hash === args.last
    puts "+ #{[command, *args].map {|s| Escape.shell_escape s }.join(' ')}"
    pos = STDOUT.pos
    TimeoutCommand.timeout_command(opts.fetch(:timeout, '1h')) {
      exec command, *args
    }
    begin
      if $?.exitstatus != 0
        if $?.exited?
          puts "exit #{$?.exitstatus}"
        elsif $?.signaled?
          puts "signal #{$?.termsig}"
        elsif $?.stopped?
          puts "stop #{$?.stopsig}"
        else
          p $?
        end
        raise CommandError.new($?, opts.fetch(:reason, command))
      end
    ensure
      if block_given?
        yield File.read(Dynamic.ref(:log_filename), nil, pos)
      end
    end
  end

  def cvs(working_dir, cvsroot, mod, branch, opts={})
    if File.directory?(working_dir)
      Dir.chdir(working_dir) {
        h1 = {}
        Dir.glob("**/CVS/Entries").each {|d|
          ds = d.split(%r{/})[0...-2]
          IO.foreach(d) {|line|
            h1[[ds, $1]] = $2 if %r{^/([^/]+)/([^/]*)/} =~ line
          }
        }
        Build.run("cvs", "-f", "-z3", "-Q", "update", "-dP", opts)
        h2 = {}
        Dir.glob("**/CVS/Entries").each {|d|
          ds = d.split(%r{/})[0...-2]
          IO.foreach(d) {|line|
            h2[[ds, $1]] = $2 if %r{^/([^/]+)/([^/]*)/} =~ line
          }
        }
        (h1.keys | h2.keys).sort.each {|k|
          f = k.flatten.join('/')
          r1 = h1[k] || 'none'
          r2 = h2[k] || 'none'
          if r1 == r2
            puts "#{f}\t#{r1}"
          else
            puts "#{f}\t#{r1} -> #{r2}"
          end
        }
      }
    else
      if branch
        Build.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-d", working_dir, "-Pr", branch, mod, opts)
      else
        Build.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-d", working_dir, "-P", mod, opts)
      end
      Dir.chdir(working_dir) {
        h1 = {}
        Dir.glob("**/CVS/Entries").each {|d|
          ds = d.split(%r{/})[0...-2]
          IO.foreach(d) {|line|
            h1[[ds, $1]] = $2 if %r{^/([^/]+)/([^/]*)/} =~ line
          }
        }
        h1.keys.sort.each {|k|
          f = k.flatten.join('/')
          puts "#{f}\t#{h1[k]}"
        }
      }
    end
  end

  def make(*targets)
    if targets.empty?
      Build.run("make")
    else
      targets.each {|target|
        Build.run("make", target, :reason => target)
      }
    end
  end

  TOP_DIRECTORY = Dir.getwd

  FileUtils.mkpath Build.build_dir
  LOCK = open("#{Build.build_dir}/.lock", "w")
  if LOCK.flock(File::LOCK_EX|File::LOCK_NB) == false
    raise "another chkbuild is running."
  end
  LOCK.sync = true
end

STDOUT.sync = true
