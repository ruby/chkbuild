require 'fileutils'
require "uri"

require "pp"

module ChkBuild; end # for testing

class ChkBuild::Build
  def git_with_file(prefix)
    n = 1
    until !File.exist?(name = "#{prefix}#{n}")
      n += 1
    end
    yield name
    if File.exist?(name)
      content = File.read(name)
      File.unlink name
    else
      content = nil
    end
    content
  end

  def git_errfile(opts)
    errcontent = git_with_file("git.err.") {|errfile|
      opts2 = opts.dup
      opts2[:stderr] = errfile
      yield opts2
    }
    if errcontent
      errcontent.gsub!(/^(remote: )?Compressing objects:.*\n/, "")
      puts errcontent if !errcontent.empty?
    end
  end

  def git(cloneurl, working_dir, opts={})
    urigen = nil
    opts = opts.dup
    opts[:section] ||= 'git'
    if opts[:github]
      urigen = GitHub.new(*opts[:github])
    end
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.git")
      Dir.chdir(working_dir) {
        old_head = git_head_commit
        git_errfile(opts) {|opts2|
          self.run "git", "pull", opts2
        }
        logs = git_oneline_logs(old_head)
        git_print_logs(old_head, logs, urigen)
      }
    else
      if File.exist?(working_dir)
        FileUtils.rm_rf(working_dir)
      end
      old_head = nil
      if File.identical?(self.build_dir, '.') &&
         !(ts = self.build_time_sequence - [self.start_time]).empty? &&
         File.directory?(old_working_dir = self.target_dir + ts.last + working_dir)
        Dir.chdir(old_working_dir) {
          old_head = git_head_commit
        }
      end
      git_errfile(opts) {|opts2|
        self.run "git", "clone", "-q", cloneurl, working_dir, opts2
      }
      Dir.chdir(working_dir) {
        logs = git_oneline_logs(old_head)
        git_print_logs(old_head, logs, urigen)
      }
    end
  end

  def github(user, project, working_dir, opts={})
    opts = opts.dup
    opts[:github] = [user, project]
    git("git://github.com/#{user}/#{project}.git", working_dir, opts)
  end

  def git_oneline_logs(old_head=nil)
    result = []
    if old_head
      command = "git log --pretty=oneline #{old_head}..HEAD"
    else
      command = "git log --pretty=oneline --max-count=1"
    end
    IO.popen(command) {|f|
      f.each_line {|line|
        # <sha1><sp><title line>
        if /\A([0-9a-fA-F]+)\s+(.*)/ =~ line
          result << [$1, $2]
        end
      }
    }
    result
  end

  def git_head_commit
    IO.popen("git rev-list --max-count=1 HEAD") {|f|
      # <sha1><LF>
      # 4db0223676a371da8c4247d9a853529ef50a3b01
      f.read.chomp
    }
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
    def initialize(user, project)
      @user = user
      @project = project
    end

    def commit_uri(commit_hash)
      # http://github.com/brixen/rubyspec/commit/b8f8eb6765afe915f2ecfdbbe59a53e6393d6865
      "http://github.com/#{@user}/#{@project}/commit/#{commit_hash}"
    end
  end

  def git_print_logs(old_head, logs, urigen=nil)
    if !old_head
      puts "last commit:"
    end
    logs.each {|commit_hash, title_line|
      if urigen
        commit = urigen.commit_uri(commit_hash)
      else
        commit = commit_hash
      end
      line = "COMMIT #{title_line}\t#{commit}"
      puts line
    }
  end
end
