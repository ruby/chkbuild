# chkbuild/build.rb - build object implementation.
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
require 'time'
require 'zlib'
require "uri"
require "tempfile"
require "pathname"
require "rbconfig"
require "rss"

require 'escape'
require 'timeoutcom'
require 'gdb'
require "lchg"
require "util"
require "erbio"

module ChkBuild
end
require 'chkbuild/options'
require 'chkbuild/target'
require 'chkbuild/title'
require "chkbuild/logfile"
require 'chkbuild/upload'

class ChkBuild::Build
  include Util

  def initialize(target, opts, depbuilds)
    @target = target
    @suffixes = Util.opts2allsuffixes(opts)
    @opts = opts
    @depbuilds = depbuilds

    @suffixed_name = self.mk_suffixed_name
    @depsuffixed_name = self.mk_depsuffixed_name
    @target_dir = ChkBuild.build_top + @depsuffixed_name
    @log_relpath = "#{@depsuffixed_name}/log"
    @public_log = ChkBuild.public_top+@log_relpath
    @current_txt_relpath = "#{@depsuffixed_name}/current.txt"
    @current_txt = ChkBuild.public_top+@current_txt_relpath
  #p [:pid, $$, @depsuffixed_name]
  end
  attr_reader :target, :suffixes, :depbuilds
  attr_reader :target_dir, :opts
  attr_reader :suffixed_name, :depsuffixed_name

  def inspect
    "\#<#{self.class}: #{self.depsuffixed_name}>"
  end

  def has_suffix?
    !@suffixes.empty?
  end

  def update_option(opts)
    @opts.update(opts)
  end

  def mk_suffixed_name
    name = @target.target_name.dup
    @suffixes.each {|suffix|
      name << '-' if /\A-/ !~ suffix
      name << suffix
    }
    name
  end

  def mk_depsuffixed_name
    name = self.suffixed_name
    @depbuilds.each {|depbuild|
      name << '_' << depbuild.suffixed_name if depbuild.has_suffix?
    }
    name
  end

  def traverse_depbuild(memo={}, &block)
    return if memo[self]
    memo[self] = true
    yield self
    @depbuilds.each {|depbuild|
      depbuild.traverse_depbuild(memo, &block)
    }
  end

  def sort_times(times)
    u, l = times.partition {|d| /Z\z/ =~ d }
    u.sort!
    l.sort!
    l + u # chkbuild used localtime at old time.
  end

  def log_time_sequence
    return [] if !@public_log.directory?
    names = @public_log.entries.map {|e| e.to_s }
    result = []
    names.each {|n|
      result << $1 if /\A(\d{8}T\d{6}Z?)(?:\.log)?\.txt\.gz\z/ =~ n
    }
    sort_times(result)
  end

  ################

  def build
    dep_dirs = []
    additional_path = []
    additional_pkg_config_path = []
    @depbuilds.each {|depbuild|
      dep_dirs << "#{depbuild.target.target_name}=#{depbuild.dir}"
      bindir = "#{depbuild.dir}/bin"
      if File.directory?(bindir) && !(Dir.entries(bindir) - %w[. ..]).empty?
	additional_path << bindir
      end
      pkg_config_path = "#{depbuild.dir}/lib/pkgconfig"
      if File.directory?(pkg_config_path) && !Dir.entries(pkg_config_path).grep(/\.pc\z/).empty?
	additional_pkg_config_path << pkg_config_path
      end
    }
    if @opts[:complete_options] && @opts[:complete_options].respond_to?(:merge_dependencies)
      @opts = @opts[:complete_options].merge_dependencies(@opts, dep_dirs)
    end
    if !additional_path.empty?
      @opts[:additional_path] = additional_path
    end
    if !additional_pkg_config_path.empty?
      @opts[:additional_pkg_config_path] = additional_pkg_config_path
    end
    status = self.build_in_child
    status.to_i == 0
  end

  BuiltHash = {}

  def set_prebuilt_info(start_time_obj, start_time)
    BuiltHash[depsuffixed_name] = [start_time_obj, start_time]
  end

  def set_built_info(start_time_obj, start_time, status, dir, version)
    BuiltHash[depsuffixed_name] = [start_time_obj, start_time, status, dir, version]
  end

  def has_prebuilt_info?
    BuiltHash[depsuffixed_name] && 2 <= BuiltHash[depsuffixed_name].length
  end

  def has_built_info?
    BuiltHash[depsuffixed_name] && 5 <= BuiltHash[depsuffixed_name].length
  end

  def prebuilt_start_time_obj
    BuiltHash[depsuffixed_name][0].utc
  end

  def prebuilt_start_time
    BuiltHash[depsuffixed_name][1]
  end

  def built_status
    BuiltHash[depsuffixed_name][2]
  end

  def built_dir
    BuiltHash[depsuffixed_name][3]
  end

  def built_version
    BuiltHash[depsuffixed_name][4]
  end

  def build_in_child
    if has_built_info?
      raise "already built: #{@depsuffixed_name}"
    end
    t = Time.now.utc
    start_time_obj = Time.utc(t.year, t.month, t.day, t.hour, t.min, t.sec)
    start_time = start_time_obj.strftime("%Y%m%dT%H%M%SZ")
    set_prebuilt_info(start_time_obj, start_time)
    target_dir = ChkBuild.build_top + @depsuffixed_name
    target_dir.mkpath
    build_dir = ChkBuild.build_top + start_time
    symlink_build_dir = target_dir + prebuilt_start_time
    build_dir.mkdir
    (build_dir+"BUILD").open("w") {|f| f.puts "#{@depsuffixed_name}/#{start_time}" }
    File.symlink build_dir.relative_path_from(symlink_build_dir.parent), symlink_build_dir
    ruby_command = RbConfig.ruby

    target_params_name = build_dir + "params.marshal"
    ibuild = ibuild_new

    File.open(target_params_name, "wb") {|f|
      Marshal.dump([ibuild, ChkBuild::Build::BuiltHash], f)
    }
    status = ChkBuild.lock_puts(@depsuffixed_name) {
      system(ruby_command, "-I#{ChkBuild::TOP_DIRECTORY}", $0,
             "internal-build",
             target_params_name.to_s)
      $?
    }
    set_built_info(start_time_obj, start_time, status, build_dir, nil)

    format_params_name = build_dir + "format_params.marshal"
    format_output_name = build_dir + "format_result.marshal"
    iformat = iformat_new

    File.open(format_params_name, "wb") {|f|
      Marshal.dump([iformat, ChkBuild::Build::BuiltHash], f)
    }
    status2 = ChkBuild.lock_puts(@depsuffixed_name) {
      system(ruby_command, "-I#{ChkBuild::TOP_DIRECTORY}", $0,
             "internal-format",
             format_params_name.to_s, format_output_name.to_s)
      $?
    }
    str = File.open(format_output_name, "rb") {|f| f.read }
    begin
      version = Marshal.load(str)
    rescue ArgumentError
      version = self.suffixed_name
    end
    set_built_info(start_time_obj, start_time, status, build_dir, version)

    run_upload_hooks(build_dir + 'log')

    return status.success? ? status2 : status
  end

  def ibuild_new
    ChkBuild::IBuild.new(
      @target, @suffixes, @suffixed_name, @depsuffixed_name, @depbuilds, @target_dir,
      @public_log, @current_txt, @opts)
  end

  def iformat_new
    ChkBuild::IFormat.new(
      @target, @suffixes, @suffixed_name, @depsuffixed_name, @depbuilds, @target_dir,
      @public_log, @current_txt, @opts)
  end

  def run_upload_hooks(log_filename)
    File.open(log_filename, 'a') {|f|
      with_stdouterr(f) {
        ChkBuild.run_upload_hooks(self.suffixed_name)
      }
    }
  end

  def start_time
    return prebuilt_start_time if has_prebuilt_info?
    raise "#{self.suffixed_name}: no start_time yet"
  end

  def success?
    if has_built_info?
      if built_status.to_i == 0
        true
      else
        false
      end
    else
      nil
    end
  end

  def dir
    return built_dir if has_built_info?
    raise "#{self.suffixed_name}: no dir yet"
  end

  def version
    return built_version if has_built_info?
    raise "#{self.suffixed_name}: no version yet"
  end

  class CommandError < StandardError
    def initialize(status, reason, message=reason)
      super message
      @reason = reason
      @status = status
    end

    attr_accessor :reason
  end
end
