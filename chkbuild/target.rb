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

class ChkBuild::Target
  def initialize(target_name, *args, &block)
    @target_name = target_name
    ChkBuild.define_build_proc(target_name, &block)
    init_target(*args)
    ChkBuild.init_title_hook(@target_name)
    ChkBuild.init_failure_hook(@target_name)
    ChkBuild.init_diff_preprocess_hook(@target_name)
    ChkBuild.init_diff_preprocess_sort(@target_name)
  end
  attr_reader :target_name, :build_proc

  def inspect
    "\#<#{self.class}: #{@target_name}>"
  end

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
      a.flatten.each {|v|
        case v
	when nil
	when ChkBuild::Target
	  opts_list << { :depend_? => v }
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
      @branches << opts
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

  def add_diff_preprocess_sort(pat) ChkBuild.define_diff_preprocess_sort(@target_name, pat) end
  def diff_preprocess_sort_pattern() ChkBuild.diff_preprocess_sort_pattern(@target_name) end

  def each_branch_opts
    @branches.each {|opts| yield opts }
  end

  def each_target(memo={}, &block)
    return if memo.include? @target_name
    @branches.each {|opts|
      dep_targets = Util.opts2aryparam(opts, :depend)
      dep_targets.each {|dep_target|
	dep_target.each_target(memo, &block)
      }
    }
    memo[@target_name] = true
    yield self
    nil
  end

  def make_build_set
    build_hash = {}
    build_set = []
    each_target {|t|
      builds = []
      t.each_branch_opts {|opts|
	dep_targets = Util.opts2aryparam(opts, :depend)
	dep_builds = dep_targets.map {|dep_target| build_hash.fetch(dep_target.target_name) }
	Util.rproduct(*dep_builds) {|dependencies|
	  builds << ChkBuild::Build.new(t, opts, dependencies)
	}
      }
      build_hash[t.target_name] = builds
      build_set << [t, builds]
    }
    build_set
  end
end
