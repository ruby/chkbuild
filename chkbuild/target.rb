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
    @build_proc = block
    @opts = ChkBuild.get_options
    @opts.update args.pop if Hash === args.last
    init_target(*args)
    @title_hook = []
    init_default_title_hooks
    @failure_hook = []
    @diff_preprocess_hook = []
    init_default_diff_preprocess_hooks
    @diff_preprocess_sort_patterns = []
  end
  attr_reader :target_name, :opts, :build_proc

  def init_target(*args)
    i = 0
    args = args.map {|a|
      i += 1
      if Array === a
        a.map {|v| String === v ? {"suffix_#{i}".intern => v} : v }
      else
        [a]
      end
    }
    @branches = []
    Util.rproduct(*args) {|a|
      opts = {}
      dep_targets = []
      a.flatten.each {|v|
        case v
	when nil
	when ChkBuild::Target
	  dep_targets << v
	when Hash
	  opts.update(v) {|k, v1, v2| v1 }
        else
	  raise "unexpected option: #{v.inspect}"
	end
      }
      h = {}
      opts.each {|k, v|
	h[$1.to_i] = v if /\Asuffix_(\d+)\z/ =~ k.to_s
      }
      suffixes2 = h.to_a.sort_by {|k, v| k }.map {|k, v| v }
      if @opts[:combination_limit]
        next if !@opts[:combination_limit].call(*suffixes2)
      end
      @branches << [suffixes2, opts, dep_targets]
    }
  end

  def init_default_title_hooks
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

  def add_title_hook(secname, &block) @title_hook << [secname, block] end
  def each_title_hook(&block) @title_hook.each(&block) end

  def add_failure_hook(secname, &block) @failure_hook << [secname, block] end
  def each_failure_hook(&block) @failure_hook.each(&block) end

  CHANGE_LINE_PAT = /^((ADD|DEL|CHG) .*\t.*->.*|COMMIT .*|last commit:)\n/
  CHANGE_LINE_PAT2 = /^(LASTLOG .*|DIRECTORY .*|FILE .*|LASTCOMMIT .*|GITOUT .*|GITERR .*)\n/

  def init_default_diff_preprocess_hooks
    add_diff_preprocess_gsub(/ # \d{4,}-\d\d-\d\dT\d\d:\d\d:\d\d[-+]\d\d:\d\d$/) {|match|
      ' # <time>'
    }
    add_diff_preprocess_gsub(CHANGE_LINE_PAT) {|match| '' }
    add_diff_preprocess_gsub(CHANGE_LINE_PAT2) {|match| '' }
    add_diff_preprocess_gsub(/timeout: the process group \d+ is alive/) {|match|
      "timeout: the process group <pgid> is alive"
    }
    add_diff_preprocess_gsub(/some descendant process in process group \d+ remain/) {|match|
      "some descendant process in process group <pgid> remain"
    }
    add_diff_preprocess_gsub(/^elapsed [0-9.]+s.*/) {|match|
      "<elapsed time>"
    }
  end

  def add_diff_preprocess_gsub_state(pat, &block)
    @diff_preprocess_hook << lambda {|line, state| line.gsub(pat) { yield $~, state } }
  end
  def add_diff_preprocess_gsub(pat, &block)
    @diff_preprocess_hook << lambda {|line, state| line.gsub(pat) { yield $~ } }
  end
  def add_diff_preprocess_hook(&block) @diff_preprocess_hook << block end
  def each_diff_preprocess_hook(&block) @diff_preprocess_hook.each(&block) end

  def add_diff_preprocess_sort(pat) @diff_preprocess_sort_patterns << pat end
  def diff_preprocess_sort_pattern()
    if @diff_preprocess_sort_patterns.empty?
      nil
    else
      /\A#{Regexp.union(*@diff_preprocess_sort_patterns)}/
    end
  end

  def each_suffixes
    @branches.each {|suffixes, opts|
      yield suffixes
    }
  end

  def each_suffixes_opts_deptargets
    @branches.each {|suffixes, opts, dep_targets|
      yield suffixes, @opts.dup.update(opts), dep_targets
    }
  end

  def update_option(hash)
    @opts.update(hash)
  end

  def make_build_objs
    return @builds if defined? @builds
    builds = []
    each_suffixes_opts_deptargets {|suffixes, opts, dep_targets|
      dep_builds = dep_targets.map {|dep_target| dep_target.make_build_objs }
      Util.rproduct(*dep_builds) {|dependencies|
        builds << ChkBuild::Build.new(self, suffixes, opts, dependencies)
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
