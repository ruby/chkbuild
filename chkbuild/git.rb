# chkbuild/git.rb - git access method
#
# Copyright (C) 2008-2012 Tanaka Akira  <akr@fsij.org>
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

module ChkBuild; end # for testing

class ChkBuild::IBuild
  def git_logfile(opts)
    with_templog(self.build_dir, "git.out.") {|outfile, outio|
      with_templog(self.build_dir, "git.err.") {|errfile, errio|
	opts2 = opts.dup
	opts2[:stdout] = outfile
	opts2[:stderr] = errfile
	begin
	  yield opts2
	ensure
	  outio.rewind
	  outcontent = outio.read
	  outcontent.gsub!(/^.*[\r\e].*\n/, "")
	  outcontent.each_line {|line| puts "GITOUT #{line}" }
	  errio.rewind
	  errcontent = errio.read
	  errcontent.gsub!(/^.*[\r\e].*\n/, "")
	  errcontent.each_line {|line| puts "GITERR #{line}" }
	end
      }
    }
  end

  def git(cloneurl, working_dir, opts={})
    network_access {
      git_internal(cloneurl, working_dir, opts)
    }
  end

  GIT_SHARED_DIR = ChkBuild.build_top + 'git-repos'

  def git_internal(cloneurl, working_dir, opts={})
    viewer = nil
    opts = opts.dup
    opts[:section] ||= "git/#{working_dir}"
    if opts[:github]
      viewer = ['GitHub', opts[:github]]
    elsif opts[:gitweb]
      viewer = ['GitWeb', opts[:gitweb]]
    elsif opts[:cgit]
      viewer = ['cgit', opts[:cgit]]
    end
    FileUtils.mkdir_p(GIT_SHARED_DIR)
    opts_shared = opts.dup
    opts_shared[:section] += "(shared)"
    cloneurl2 = "#{GIT_SHARED_DIR}/#{working_dir}.git"
    branch = opts[:branch] || git_default_branch(cloneurl)
    Dir.chdir(GIT_SHARED_DIR) {
      if File.directory?(cloneurl2) &&
         Dir.chdir(cloneurl2) { `git config --get remote.origin.url` }.chomp != cloneurl
	FileUtils.rm_rf(cloneurl2)
      end
      if File.directory?(cloneurl2)
	Dir.chdir(cloneurl2) {
	  git_logfile(opts_shared) {|opts2|
	    self.run("git", "fetch", "--depth", "1", opts2)
	  }
	}
      else
	FileUtils.rm_rf(cloneurl2) if File.exist?(cloneurl2)
	pdir = File.dirname(cloneurl2)
	FileUtils.mkdir_p(pdir) if !File.directory?(pdir)
	git_logfile(opts_shared) {|opts2|
	  self.run "git", "clone", "--depth", "1", "-q", "--mirror", cloneurl, cloneurl2, opts2
	}
      end
    }
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.git")
      Dir.chdir(working_dir) {
        git_logfile(opts) {|opts2|
          self.run "git", "pull", "--depth", "1", opts2
        }
      }
    else
      FileUtils.rm_rf(working_dir) if File.exist?(working_dir)
      pdir = File.dirname(working_dir)
      FileUtils.mkdir_p(pdir) if !File.directory?(pdir)
      git_logfile(opts) {|opts2|
	command = ["git", "clone", "--depth", "1", "-q"]
	command << '--branch' << branch if branch
	command << cloneurl2
	command << working_dir
	command << opts2
        self.run(*command)
      }
    end
    Dir.chdir(working_dir) {
      new_head = git_head_commit
      new_head_log = git_single_log(new_head)
      new_head_log.each_line {|line|
	puts "LASTLOG #{line}"
      }
      puts "CHECKOUT git #{cloneurl} #{working_dir}"
      puts "LASTCOMMIT #{new_head}"
      branch = git_current_branch
      puts "BRANCH #{branch}"
    }
  end

  def github(user, project, working_dir, opts={})
    git("git://github.com/#{u user}/#{u project}.git", working_dir, opts)
  end

  def git_single_log(rev)
    command = "git log --max-count=1 #{rev}"
    IO.popen(command) {|f|
      f.read
    }
  end

  def git_head_commit
    IO.popen("git rev-list --max-count=1 HEAD") {|f|
      # <sha1><LF>
      # 4db0223676a371da8c4247d9a853529ef50a3b01
      f.read.chomp
    }
  end

  def git_current_branch
    command = "git rev-parse --abbrev-ref HEAD"
    IO.popen(command) {|f|
      f.read.chomp
    }
  end

  def git_default_branch(git_url)
    remote_heads = IO.popen(['git', 'ls-remote', git_url, 'HEAD', 'refs/heads/*']) {|f| f.readlines }
    head_commit = nil
    h = {}
    remote_heads.each {|line|
      next if /\A([0-9a-f]+)\s+(\S+)\n\z/ !~ line
      commit = $1
      ref = $2
      case ref
      when 'HEAD'
        head_commit = commit
      when %r{\Arefs/heads/}
        h[commit] = $'
      end
    }
    if head_commit && h.has_key?(head_commit)
      h[head_commit]
    else
      nil
    end
  end
end

class ChkBuild::IFormat
  GIT_SHARED_DIR = ChkBuild.build_top + 'git-repos'

  def git_oneline_logs2(old_head, new_head)
    result = []
    #command = "git log --pretty=oneline #{old_head}..#{new_head}"
    command = "git log --pretty='format:%H [%an] %s' #{old_head}..#{new_head}"
    IO.popen(command) {|f|
      f.each_line {|line|
        # <sha1><sp><title line>
        if /\A([0-9a-fA-F]+)\s+(.*)/ =~ line
          result << [$1, $2]
        end
      }
    }
    result.reverse!
    result
  end

  def git_revisions
    h = IO.popen("git ls-tree -z -r HEAD") {|f|
      git_parse_status(f)
    }
    IO.popen("git rev-list --max-count=1 HEAD") {|f|
      # <sha1><LF>
      # 4db0223676a371da8c4247d9a853529ef50a3b01
      commit_hash = f.read.chomp
      h[nil] = commit_hash
    }
    h
  end

  def git_parse_status(f)
    h = {}
    f.each_line("\0") {|line|
      # <mode> SP <type> SP <object> TAB <file>\0
      # 100644 blob 9518934185ea26856cf1bcdf75f7cc51fcd82534    core/array/allocate_spec.rb
      if /\A\d+ [^ ]+ ([0-9a-fA-F]+)\t([^\0]+)\0\z/ =~ line
        rev = $1
        path = $2
        h[path] = rev
      end
    }
    h
  end

  def git_path_sort(ary)
    ary.sort_by {|path|
      path.gsub(%r{([^/]+)(/|\z)}) {
        if $2 == ""
          if $1 == '.'
            "A"
          else
            "B#{$1}"
          end
        else
          "C#{$1}\0"
        end
      }
    }
  end

  class GitHub
    def initialize(uri)
      # https://github.com/rubyspec/rubyspec
      @user, @project = uri.split(%r{/})[-2, 2]
    end

    def call(commit_hash)
      # https://github.com/rubyspec/rubyspec/commit/b8f8eb6765afe915f2ecfdbbe59a53e6393d6865
      "https://github.com/#{@user}/#{@project}/commit/#{commit_hash}"
    end
  end

  class GitWeb
    def initialize(uri)
      # http://git.savannah.gnu.org/gitweb/?p=autoconf.git
      @uri = URI(uri)
      @git_project_name = CGI.parse(@uri.query)['p'][0]
    end

    def call(hash)
      # http://git.savannah.gnu.org/gitweb/?p=autoconf.git;a=commit;h=cc2118d83698708c7c0334ad72f2cd03c4f81f0b
      uri = @uri.dup
      query = [
        ['p', @git_project_name],
        ['a', 'commit'],
        ['h', hash]
      ]
      uri.query = query.map {|k, v| "#{k}=#{CGI.escape v}" }.join(';')
      uri.to_s
    end
  end

  class Cgit
    def initialize(uri)
      # http://git.savannah.gnu.org/cgit/autoconf.git
      @uri = uri
    end

    def call(hash)
      # http://git.savannah.gnu.org/cgit/autoconf.git/commit/?id=7fbb553727ed7e0e689a17594b58559ecf3ea6e9
      "#{@uri}/commit/?id=#{hash}"
    end
  end

  def git_print_logs(working_dir, logs, urigen, out)
    logs.each {|commit_hash, title_line|
      if urigen
        commit = urigen.call(commit_hash)
      else
        commit = commit_hash
      end
      line = "COMMIT #{working_dir} #{title_line}\t#{commit}"
      out.puts line
    }
  end

  def output_git_change_lines(checkout_line, lines1, lines2, out)
    if /CHECKOUT git (\S+) (\S+)/ !~ checkout_line
      out.puts "unexpected checkout line: #{checkout_line}"
      return
    end
    cloneurl = $1
    working_dir = $2
    urigen = ChkBuild.find_file_changes_viewer('git', cloneurl)

    lastcommit1 = lines1.find {|line| /\ALASTCOMMIT / =~ line }
    lastrev1 = $1 if lastcommit1 && /\ALASTCOMMIT ([0-9a-fA-F]+)/ =~ lastcommit1
    lastcommit2 = lines2.find {|line| /\ALASTCOMMIT / =~ line }
    lastrev2 = $1 if lastcommit2 && /\ALASTCOMMIT ([0-9a-fA-F]+)/ =~ lastcommit2
    if !lastrev1 || !lastrev2
      out.puts "no last revision found."
      return
    end

    cloneurl2 = "#{GIT_SHARED_DIR}/#{working_dir}.git"
    Dir.chdir(cloneurl2) {
      logs = git_oneline_logs2(lastrev1, lastrev2)
      git_print_logs(working_dir, logs, urigen, out)
    }
  end
end

# segment       = *pchar
# pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
# unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
# pct-encoded   = "%" HEXDIG HEXDIG
# sub-delims    = "!" / "$" / "&" / "'" / "(" / ")"
#               / "*" / "+" / "," / ";" / "="
segment_regexp = '(?:[A-Za-z0-9\-._~!$&\'()*+,;=:@]|%[0-9A-Fa-f][0-9A-Fa-f])*'

ChkBuild.define_file_changes_viewer('git',
  %r{\A(?:git|https)://github\.com/(#{segment_regexp})/(#{segment_regexp})\.git\z}o) {
  |match, reptype, pat, checkout_line|
  user = match[1]
  project = match[2]
  ChkBuild::IFormat::GitHub.new("https://github.com/#{user}/#{project}")
}

ChkBuild.define_file_changes_viewer('git',
  %r{\Agit://(?:git\.savannah\.gnu\.org|git\.sv\.gnu\.org)/(#{segment_regexp})\.git\z}o) {
  |match, reptype, pat, checkout_line|
  # git://git.savannah.gnu.org/autoconf.git
  # http://git.savannah.gnu.org/cgit/autoconf.git
  project_basename = match[1]
  ChkBuild::IFormat::Cgit.new("http://git.savannah.gnu.org/cgit/#{project_basename}.git")

  # # GitWeb:
  # # http://git.savannah.gnu.org/gitweb/?p=autoconf.git
  # project_basename = CGI.escape(CGI.unescape($1)) # segment to query component
  # ChkBuild::IFormat::GitWeb.new("http://git.savannah.gnu.org/gitweb/?p=#{project_basename}.git")
}

ChkBuild.define_title_hook(nil, %r{\Agit/}) {|title, logs|
  logs.each {|log|
    next unless url = /^CHECKOUT git (\S+)/.match(log)
    next unless lastcommit = /^LASTCOMMIT ([0-9a-f]+)$/.match(log)
    title.update_hidden_title(url[1], lastcommit[1])
  }
}

