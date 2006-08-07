require 'fileutils'

class ChkBuild::Build
  def svn(svnroot, rep_dir, working_dir, opts={})
    url = svnroot + '/' + rep_dir
    opts = opts.dup
    opts[:section] ||= 'svn'
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.svn")
      Dir.chdir(working_dir) {
        self.run "svn", "cleanup", opts
        opts[:section] = nil
        h1 = svn_revisions
        self.run "svn", "update", "-q", opts
        h2 = svn_revisions
        svn_print_revisions(h1, h2, opts[:viewcvs]+'/'+rep_dir)
      }
    else
      if File.exist?(working_dir)
        FileUtils.rm_rf(working_dir)
      end
      self.run "svn", "checkout", "-q", url, working_dir, opts
    end
  end

  def svn_revisions
    h = {}
    IO.popen("svn status -v") {|f|
      f.each {|line|
        if /\d+\s+(\d+)\s+\S+\s+(\S+)/ =~ line
          rev = $1.to_i
          path = $2
          h[path] = rev
        end
      }
    }
    h
  end

  def svn_print_revisions(h1, h2, viewcvs=nil)
    changes = 'changes:'
    (h1.keys|h2.keys).sort.each {|f|
      r1 = h1[f] || 'none'
      r2 = h2[f] || 'none'
      next if r1 == r2
      if changes
        puts changes
        changes = nil
      end
      line = "#{f}\t#{r1} -> #{r2}"
      if viewcvs
        diff_url = viewcvs.dup
        diff_url << '/' << f if f != '.'
        diff_url << "?r1=#{r1}&r2=#{r2}"
        line << " " << diff_url
      end
      puts line
    }
  end
end
