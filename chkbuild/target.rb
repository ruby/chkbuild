# chkbuild/target.rb - target class definition
#
# Copyright (C) 2006-2012 Tanaka Akira  <akr@fsij.org>
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
    ChkBuild.define_build_proc(target_name, &block) if block
    init_target(*args)
  end
  attr_reader :target_name

  def inspect
    "\#<#{self.class}: #{@target_name}>"
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
      if opts[:complete_options] && opts[:complete_options].respond_to?(:call)
        opts = opts[:complete_options].call(opts)
	next if !opts
      end
      @branches << opts
    }
  end

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
	  all_depbuilds = {}
	  found_inconsistency = false
	  dependencies.each {|db|
	    db.traverse_depbuild {|db2|
	      db3 = all_depbuilds[db2.target.target_name]
	      if db3 && db3 != db2
		found_inconsistency = true
	      end
	      all_depbuilds[db2.target.target_name] = db2
	    }
	  }
	  next if found_inconsistency
	  dependencies = all_depbuilds.map {|target_name, depbuild| depbuild }.sort_by {|db| db.target.target_name }
	  builds << ChkBuild::Build.new(t, opts, dependencies)
	}
      }
      build_hash[t.target_name] = builds
      build_set << [t, builds]
    }
    build_set
  end
end
