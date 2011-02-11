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
