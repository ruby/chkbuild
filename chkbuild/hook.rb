# chkbuild/hook.rb - hook definitions
#
# Copyright (C) 2011 Tanaka Akira  <akr@fsij.org>
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
    init_default_title_hooks(target_name) if @title_hook_hash[target_name].empty?
  end
  def ChkBuild.define_title_hook(target_name, secname, &block)
    @title_hook_hash[target_name] ||= []
    @title_hook_hash[target_name] << [secname, block]
  end
  def ChkBuild.fetch_title_hook(target_name)
    @title_hook_hash.fetch(target_name)
  end

  def ChkBuild.init_default_title_hooks(target_name)
    define_title_hook(target_name, 'success') {|title, log|
      title.update_title(:status) {|val| 'success' if !val }
    }
    define_title_hook(target_name, 'failure') {|title, log|
      title.update_title(:status) {|val|
        if !val
          line = /\n/ =~ log ? $` : log
          line = line.strip
          line if !line.empty?
        end
      }
    }
    define_title_hook(target_name, nil) {|title, log|
      num_warns = log.scan(/warn/i).length
      title.update_title(:warn) {|val| "#{num_warns}W" } if 0 < num_warns
    }
    define_title_hook(target_name, 'dependencies') {|title, log|
      dep_versions = []
      title.logfile.dependencies.each {|suffixed_name, time, ver|
        dep_versions << "(#{ver})"
      }
      title.update_title(:dep_versions, dep_versions)
    }
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

  @diff_preprocess_sort_patterns_hash = {}
  def ChkBuild.init_diff_preprocess_sort(target_name)
    @diff_preprocess_sort_patterns_hash[target_name] ||= []
  end
  def ChkBuild.define_diff_preprocess_sort(target_name, pat)
    @diff_preprocess_sort_patterns_hash[target_name] << pat
  end
  def ChkBuild.diff_preprocess_sort_pattern(target_name)
    if @diff_preprocess_sort_patterns_hash[target_name].empty?
      nil
    else
      /\A#{Regexp.union(*@diff_preprocess_sort_patterns_hash[target_name])}/
    end
  end
end

