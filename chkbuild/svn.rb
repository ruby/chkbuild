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
        dir = File.directory?(path)
        h[path] = [rev, dir]
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

  def svn_rev_uri(viewvc, r)
    return nil if !viewvc
    svn_extend_uri(URI.parse(viewvc), "", [['view', 'rev'], ['revision', r.to_s]]).to_s
  end

  def svn_markup_uri(viewvc, d, f, r)
    return nil if !viewvc
    svn_extend_uri(URI.parse(viewvc), "/#{d}/#{f}", [['view', 'markup'], ['pathrev', r.to_s]]).to_s
  end

  def svn_dir_uri(viewvc, d, f, r)
    return nil if !viewvc
    svn_extend_uri(URI.parse(viewvc), "/#{d}/#{f}", [['pathrev', r.to_s]]).to_s
  end

  def svn_diff_uri(viewvc, d, f, r1, r2)
    return nil if !viewvc
    svn_extend_uri(URI.parse(viewvc), "/#{d}/#{f}", [
      ['p1', "#{d}/#{f}"],
      ['r1', r1.to_s],
      ['r2', r2.to_s],
      ['pathrev', r2.to_s]]).to_s
  end

  def svn_extend_uri(uri, path, params)
    path0 = uri.path
    path0 << path
    uri.path = path0
    query = Escape.html_form(params)
    (uri.query || '').split(/[;&]/).each {|param| query << ';' << param }
    uri.query = query
    uri
  end

  def svn_print_changes(h1, h2, viewvc=nil, rep_dir=nil)
    top_r1, _ = h1['.']
    top_r2, _ = h2['.']
    h1.delete '.'
    h2.delete '.'
    return if top_r1 == top_r2
    svn_print_chg_line('.', top_r1, top_r2, svn_rev_uri(viewvc, top_r2))
    svn_path_sort(h1.keys|h2.keys).each {|f|
      r1, d1 = h1[f] || ['none', nil]
      r2, d2 = h2[f] || ['none', nil]
      next if r1 == r2 # no changes
      next if d1 && d2 # skip directory changes
      if !d1 && !d2 && r1 != 'none' && r2 != 'none'
        svn_print_chg_line(f, r1, r2,
          svn_diff_uri(viewvc, rep_dir, f, top_r1, top_r2))
      else
        svn_print_del_line(f, r1,
          d1 ? svn_dir_uri(viewvc, rep_dir, f, top_r1) :
               svn_markup_uri(viewvc, rep_dir, f, top_r1)) if r1 != 'none'
        svn_print_add_line(f, r2,
          d2 ? svn_dir_uri(viewvc, rep_dir, f, top_r2) :
               svn_markup_uri(viewvc, rep_dir, f, top_r2)) if r2 != 'none'
      end
    }
  end

  def svn_print_chg_line(f, r1, r2, uri)
    line = "CHG #{f}\t#{r1}->#{r2}"
    line << "\t" << uri.to_s if uri
    puts line
  end

  def svn_print_del_line(f, r, uri)
    line = "DEL #{f}\t#{r}->none"
    line << "\t" << uri.to_s if uri
    puts line
  end

  def svn_print_add_line(f, r, uri)
    line = "ADD #{f}\tnone->#{r}"
    line << "\t" << uri.to_s if uri
    puts line
  end

end
