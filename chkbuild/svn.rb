require 'fileutils'
require "uri"

module ChkBuild; end # for testing
class ChkBuild::Build
  def svn(svnroot, rep_dir, working_dir, opts={})
    url = svnroot + '/' + rep_dir
    opts = opts.dup
    opts[:section] ||= 'svn'
    viewvc = opts[:viewvc]||opts[:viewcvs]
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.svn")
      Dir.chdir(working_dir) {
        self.run "svn", "cleanup", opts
        opts[:section] = nil
        h1 = svn_revisions
        self.run "svn", "update", "-q", opts
        h2 = svn_revisions
        svn_print_changes(h1, h2, viewvc, rep_dir)
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
          h1 = svn_revisions
        }
      end
      self.run "svn", "checkout", "-q", url, working_dir, opts
      Dir.chdir(working_dir) {
        h2 = svn_revisions
        svn_print_changes(h1, h2, viewvc, rep_dir) if h1
      }
    end
  end

  def svn_revisions
    IO.popen("svn status -v") {|f|
      svn_parse_status(f)
    }
  end

  def svn_parse_status(f)
    h = {}
    f.each {|line|
      if /\d+\s+(\d+)\s+\S+\s+(\S+)/ =~ line
        rev = $1.to_i
        path = $2
        h[path] = rev
      end
    }
    h
  end

  def svn_path_sort(ary)
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

  def svn_uri(viewcvs, d, f, r1, top_r1, r2)
    uri = URI.parse(viewcvs)
    if f == '.'
      query = Escape.html_form([['view', 'rev'], ['revision', r2.to_s]])
      (uri.query || '').split(/[;&]/).each {|param| query << ';' << param }
      uri.query = query
      return uri.to_s
    end
    df = d + '/' + f
    path = uri.path
    path <<  '/' << df
    uri.path = path
    if r1 == 'none'
      query = Escape.html_form([['view', 'markup'], ['pathrev', r2.to_s]])
    elsif r2 == 'none'
      query = Escape.html_form([['view', 'markup'], ['pathrev', r2.to_s]])
    else
      query = Escape.html_form([
        ["p1", df],
        ["r1", top_r1.to_s],
        ["r2", r2.to_s],
        ["pathrev", r2.to_s]])
    end
    (uri.query || '').split(/[;&]/).each {|param| query << ';' << param }
    uri.query = query
    uri.to_s
  end

  def svn_print_changes(h1, h2, viewcvs=nil, rep_dir=nil)
    d1 = {}; h1.keys.each {|k| d1[$`] = true if %r{/[^/]*\z} =~ k }
    d2 = {}; h2.keys.each {|k| d2[$`] = true if %r{/[^/]*\z} =~ k }
    d1.each_key {|k|
      next if !d2.include?(k)
      h1.delete k
      h2.delete k
    }
    top_r1 = h1['.']
    svn_path_sort(h1.keys|h2.keys).each {|f|
      r1 = h1[f] || 'none'
      r2 = h2[f] || 'none'
      next if r1 == r2
      if r1 == 'none'
        line = "ADD"
      elsif r2 == 'none'
        line = "DEL"
      else
        line = "CHG"
      end
      line << " #{f}\t#{r1}->#{r2}"
      line << "\t" << svn_uri(viewcvs, rep_dir, f, r1, top_r1, r2) if viewcvs
      puts line
    }
  end
end
