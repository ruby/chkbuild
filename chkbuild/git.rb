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
    errcontent.gsub!(/^(remote: )?Compressing objects:.*\n/, "")
    puts errcontent
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
        h1 = git_revisions
        #pp h1
        git_errfile(opts) {|opts2|
          self.run "git", "pull", opts2
        }
        h2 = git_revisions
        #pp h2
        git_print_changes(h1, h2, urigen)
      }
    else
      if File.exist?(working_dir)
        FileUtils.rm_rf(working_dir)
      end
      h1 = h2 = nil
      if File.identical?(self.build_dir, '.') &&
         !(ts = self.build_time_sequence - [self.start_time]).empty? &&
         File.directory?(old_working_dir = self.target_dir + ts.last + working_dir)
        Dir.chdir(old_working_dir) {
          h1 = git_revisions
          #pp h1
        }
      end
      git_errfile(opts) {|opts2|
        self.run "git", "clone", "-q", cloneurl, working_dir, opts2
      }
      Dir.chdir(working_dir) {
        h2 = git_revisions
        #pp h2
        git_print_changes(h1, h2, urigen) if h1
      }
    end
  end

  def github(user, project, working_dir, opts={})
    opts = opts.dup
    git("git://github.com/#{user}/#{project}.git", working_dir, :github=>[user, project])
  end

  def git_revisions
    h = IO.popen("git ls-tree -z -r HEAD") {|f|
      git_parse_status(f)
    }
    IO.popen("git-log --pretty=oneline --max-count=1") {|f|
      # <sha1><SP><title-line>
      # 4db0223676a371da8c4247d9a853529ef50a3b01 use send(cmd).
      commit_hash = f.read[/\A[0-9a-fA-F]*/]
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

  def git_print_changes(h1, h2, urigen=nil)
    commit_hash_old = h1[nil]
    commit_hash_new = h2[nil]
    h1.delete nil
    h2.delete nil
    if urigen
      puts "last commit: #{urigen.commit_uri(commit_hash_new)}"
    end
    git_path_sort(h1.keys|h2.keys).each {|f|
      r1 = h1[f] || ['none', nil]
      r2 = h2[f] || ['none', nil]
      next if r1 == r2 # no changes
      if r1 != 'none' && r2 != 'none'
        git_print_chg_line(f, r1, r2)
      else
        git_print_del_line(f, r1) if r1 != 'none'
        git_print_add_line(f, r2) if r2 != 'none'
      end
    }
  end

  def git_print_chg_line(f, r1, r2)
    line = "CHG #{f}\t#{r1}->#{r2}"
    puts line
  end

  def git_print_del_line(f, r)
    line = "DEL #{f}\t#{r}->none"
    puts line
  end

  def git_print_add_line(f, r)
    line = "ADD #{f}\tnone->#{r}"
    puts line
  end

end
