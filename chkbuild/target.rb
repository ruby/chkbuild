# chkbuild/target.rb - target class definition
#
# Copyright (C) 2006-2011 Tanaka Akira  <akr@fsij.org>
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

module ChkBuild
  @build_proc_hash = {}
  def ChkBuild.define_build_proc(target_name, &block)
    raise ArgumentError, "already defined target: #{target_name.inspect}" if @build_proc_hash.include? target_name
    @build_proc_hash[target_name] = block
  end
  def ChkBuild.fetch_build_proc(target_name)
    @build_proc_hash.fetch(target_name)
  end

  @title_hook_hash = {}
  def ChkBuild.init_title_hook(target_name)
    @title_hook_hash[target_name] ||= []
  end
  def ChkBuild.define_title_hook(target_name, secname, &block)
    @title_hook_hash[target_name] ||= []
    @title_hook_hash[target_name] << [secname, block]
  end
  def ChkBuild.fetch_title_hook(target_name)
    @title_hook_hash.fetch(target_name)
  end

  @failure_hook_hash = {}
  def ChkBuild.init_failure_hook(target_name)
    @failure_hook_hash[target_name] ||= []
  end
  def ChkBuild.define_failure_hook(target_name, secname, &block)
    @failure_hook_hash[target_name] ||= []
    @failure_hook_hash[target_name] << [secname, block]
  end
  def ChkBuild.fetch_failure_hook(target_name)
    @failure_hook_hash.fetch(target_name)
  end

  @diff_preprocess_hook_hash = {}
  def ChkBuild.init_diff_preprocess_hook(target_name)
    @diff_preprocess_hook_hash[target_name] ||= []
    init_default_diff_preprocess_hooks(target_name) if @diff_preprocess_hook_hash[target_name].empty?
  end
  def ChkBuild.define_diff_preprocess_hook(target_name, &block)
    @diff_preprocess_hook_hash[target_name] << block
  end
  def ChkBuild.fetch_diff_preprocess_hook(target_name)
    @diff_preprocess_hook_hash.fetch(target_name)
  end

  def ChkBuild.define_diff_preprocess_gsub_state(target_name, pat, &block)
    define_diff_preprocess_hook(target_name) {|line, state| line.gsub(pat) { yield $~, state } }
  end
  def ChkBuild.define_diff_preprocess_gsub(target_name, pat, &block)
    define_diff_preprocess_hook(target_name) {|line, state| line.gsub(pat) { yield $~ } }
  end

  CHANGE_LINE_PAT = /^((ADD|DEL|CHG) .*\t.*->.*|COMMIT .*|last commit:)\n/
  CHANGE_LINE_PAT2 = /^(LASTLOG .*|DIRECTORY .*|FILE .*|LASTCOMMIT .*|GITOUT .*|GITERR .*|SVNOUT .*)\n/

  def ChkBuild.init_default_diff_preprocess_hooks(target_name)
    define_diff_preprocess_gsub(target_name, / # \d{4,}-\d\d-\d\dT\d\d:\d\d:\d\d[-+]\d\d:\d\d$/) {|match|
      ' # <time>'
    }
    define_diff_preprocess_gsub(target_name, CHANGE_LINE_PAT) {|match| '' }
    define_diff_preprocess_gsub(target_name, CHANGE_LINE_PAT2) {|match| '' }
    define_diff_preprocess_gsub(target_name, /timeout: the process group \d+ is alive/) {|match|
      "timeout: the process group <pgid> is alive"
    }
    define_diff_preprocess_gsub(target_name, /some descendant process in process group \d+ remain/) {|match|
      "some descendant process in process group <pgid> remain"
    }
    define_diff_preprocess_gsub(target_name, /^elapsed [0-9.]+s.*/) {|match|
      "<elapsed time>"
    }
  end
end

class ChkBuild::Target
  def initialize(target_name, *args, &block)
    @target_name = target_name
    ChkBuild.define_build_proc(target_name, &block)
    init_target(*args)
    ChkBuild.init_title_hook(@target_name)
    init_default_title_hooks
    ChkBuild.init_failure_hook(@target_name)
    ChkBuild.init_diff_preprocess_hook(@target_name)
    @diff_preprocess_sort_patterns = []
  end
  attr_reader :target_name, :opts, :build_proc

  def build_proc
    ChkBuild.fetch_build_proc(@target_name)
  end

  def init_target(*args)
    args = args.map {|a|
      if Array === a
        a.map {|v| String === v ? {:suffix_? => v} : v }
      elsif String === a
        [{:suffix_? => a}]
      else
        [a]
      end
    }
    @branches = []
    Util.rproduct(*args) {|a|
      opts_list = []
      dep_targets = []
      a.flatten.each {|v|
        case v
	when nil
	when ChkBuild::Target
	  dep_targets << v
	when Hash
	  opts_list << v
        else
	  raise "unexpected option: #{v.inspect}"
	end
      }
      opts_list << ChkBuild.get_options
      opts = Util.merge_opts(opts_list)
      if opts[:complete_options]
        opts = opts[:complete_options].call(opts)
	next if !opts
      end
      @branches << [opts, dep_targets]
    }
  end

  def init_default_title_hooks
    return if !ChkBuild.fetch_title_hook(@target_name).empty?
    add_title_hook('success') {|title, log|
      title.update_title(:status) {|val| 'success' if !val }
    }
    add_title_hook('failure') {|title, log|
      title.update_title(:status) {|val|
        if !val
          line = /\n/ =~ log ? $` : log
          line = line.strip
          line if !line.empty?
        end
      }
    }
    add_title_hook(nil) {|title, log|
      num_warns = log.scan(/warn/i).length
      title.update_title(:warn) {|val| "#{num_warns}W" } if 0 < num_warns
    }
    add_title_hook('dependencies') {|title, log|
      dep_versions = []
      title.logfile.dependencies.each {|suffixed_name, time, ver|
        dep_versions << "(#{ver})"
      }
      title.update_title(:dep_versions, dep_versions)
    }
  end

  def add_title_hook(secname, &block) ChkBuild.define_title_hook(@target_name, secname, &block) end
  def each_title_hook(&block) ChkBuild.fetch_title_hook(@target_name).each(&block) end

  def add_failure_hook(secname, &block) ChkBuild.define_failure_hook(@target_name, secname, &block) end
  def each_failure_hook(&block) ChkBuild.fetch_failure_hook(@target_name).each(&block) end

  def add_diff_preprocess_gsub_state(pat, &block) ChkBuild.define_diff_preprocess_gsub_state(@target_name, pat, &block) end
  def add_diff_preprocess_gsub(pat, &block) ChkBuild.define_diff_preprocess_gsub(@target_name, pat, &block) end
  def add_diff_preprocess_hook(&block) ChkBuild.define_diff_preprocess_hook(&block) end
  def each_diff_preprocess_hook(&block) ChkBuild.fetch_diff_preprocess_hook(@target_name).each(&block) end

  def add_diff_preprocess_sort(pat) @diff_preprocess_sort_patterns << pat end
  def diff_preprocess_sort_pattern()
    if @diff_preprocess_sort_patterns.empty?
      nil
    else
      /\A#{Regexp.union(*@diff_preprocess_sort_patterns)}/
    end
  end

  def make_build_objs
    return @builds if defined? @builds
    builds = []
    @branches.each {|opts, dep_targets|
      dep_builds = dep_targets.map {|dep_target| dep_target.make_build_objs }
      Util.rproduct(*dep_builds) {|dependencies|
        builds << ChkBuild::Build.new(self, opts, dependencies)
      }
    }
    @builds = builds
  end
  def each_build_obj(&block)
    make_build_objs.each(&block)
  end

  def make_result
    return @result if defined? @result
    succeed = Result.new
    each_build_obj {|build|
      next if block_given? && !yield(build)
      if build.depbuilds.all? {|depbuild| depbuild.success? }
        succeed.add(build) if build.build
      end
    }
    @result = succeed
    succeed
  end

  def result
    return @result if defined? @result
    raise "#{@target_name}: no result yet"
  end

  class Result
    include Enumerable

    def initialize
      @list = []
    end

    def add(elt)
      @list << elt
    end

    def each
      @list.each {|elt| yield elt }
    end
  end
end
