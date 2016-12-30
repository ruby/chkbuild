# chkbuild/svn.rb - svn access methods
#
# Copyright (C) 2006-2012 Tanaka Akira  <akr@fsij.org>
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

module ChkBuild::SVNUtil
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
end

class ChkBuild::IBuild
  include ChkBuild::SVNUtil

  def svn(svnroot, rep_dir, working_dir, opts={})
    network_access {
      svn_internal(svnroot, rep_dir, working_dir, opts)
      opts = opts.dup
      opts[:section] = nil
      svn_info(working_dir, opts)
    }
  end

  def svn_internal(svnroot, rep_dir, working_dir, opts={})
    url = svnroot + '/' + rep_dir
    opts = opts.dup
    opts[:section] ||= "svn/#{working_dir}"
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.svn")
      Dir.chdir(working_dir) {
        self.run "svn", "cleanup", opts
        opts[:section] = nil
	svn_logfile(opts) {|outio, opts2|
	  opts2[:output_interval_file_list] = [STDOUT, STDERR, outio]
	  self.run "svn", "update", opts2
	}
        h2 = svn_revisions
	svn_print_lastlog(h2['.'][0])
	svn_print_revisions(svnroot, rep_dir, h2)
      }
    else
      if File.exist?(working_dir)
        FileUtils.rm_rf(working_dir)
      end
      h2 = nil
      svn_logfile(opts) {|outio, opts2|
        opts2[:output_interval_file_list] = [STDOUT, STDERR, outio]
	self.run "svn", "checkout", url, working_dir, opts2
      }
      opts[:section] = nil
      Dir.chdir(working_dir) {
        h2 = svn_revisions
	svn_print_lastlog(h2['.'][0])
	svn_print_revisions(svnroot, rep_dir, h2)
      }
    end
  end

  def svn_logfile(opts)
    with_templog(self.build_dir, "svn.out.") {|outfile, outio|
      opts2 = opts.dup
      opts2[:stdout] = outfile
      begin
	yield outio, opts2
      ensure
	outio.rewind
	outio.each_line {|line| puts "SVNOUT #{line}" }
      end
    }
  end

  def svn_info(working_dir, opts={})
    opts = opts.dup
    opts["ENV:LC_ALL"] = "C"
    opts[:section] = 'svn-info' unless opts.has_key? :section
    Dir.chdir(working_dir) {
      self.run "svn", "info", opts
    }
  end

  def svn_revisions
    IO.popen("svn status -v") {|f|
      svn_parse_status(f)
    }
  end

  def svn_parse_status(f)
    h = {}
    f.each {|line|
      if /\d+\s+(\d+)\s+\S+\s+(.+)/ =~ line
        rev = $1.to_i
        path = $2
        ftype = File.ftype(path)
        path << '/' if ftype == 'directory' && path != '.'
        h[path] = [rev, ftype]
      end
    }
    h
  end

  def svn_print_lastlog(rev)
    IO.popen("svn log -r #{rev}") {|f|
      f.each_line {|line|
        puts "LASTLOG #{line}"
      }
    }
  end

  def svn_print_revisions(svnroot, rep_dir, h)
    puts "CHECKOUT svn #{svnroot} #{rep_dir}"
    svn_path_sort(h.keys).each {|f|
      r, ftype = h[f]
      if ftype == 'directory'
	puts "DIRECTORY #{f}\t#{r}"
      else
        digest = sha256_digest_file(f)
	puts "FILE #{f}\t#{r}\t#{digest}"
      end
    }
  end
end

class ChkBuild::IFormat
  include ChkBuild::SVNUtil

  def svn_restore_file_info(lines)
    h = {}
    lines.each {|line|
      case line
      when /\ADIRECTORY (\S+)\t(\S+)/
        h[$1] = [$2.to_i, 'directory']
      when /\AFILE (\S+)\t(\S+)/
        h[$1] = [$2.to_i, 'file']
      end
    }
    h
  end

  def output_svn_change_lines(checkout_line, lines1, lines2, out)
    if /CHECKOUT svn (\S+) (\S+)/ !~ checkout_line
      out.puts "unexpected checkout line: #{checkout_line}"
      return
    end
    svnroot = $1
    rep_dir = $2
    viewer = ChkBuild.find_file_changes_viewer('svn', "#{svnroot} #{rep_dir}")
    h1 = svn_restore_file_info(lines1)
    h2 = svn_restore_file_info(lines2)
    svn_print_changes(h1, h2, viewer, out)
  end

  def svn_rev_uri(viewer, r)
    return nil if !viewer
    viewer.rev_uri(r)
  end

  def svn_markup_uri(viewer, f, r)
    return nil if !viewer
    viewer.markup_uri(nil, f, r)
  end

  def svn_dir_uri(viewer, f, r)
    return nil if !viewer
    viewer.dir_uri(nil, f, r)
  end

  def svn_diff_uri(viewer, f, r1, r2)
    return nil if !viewer
    viewer.diff_uri(nil, f, r1, r2)
  end

  def svn_print_changes(h1, h2, viewer=nil, out=STDOUT)
    top_r1, _ = h1['.']
    top_r2, _ = h2['.']
    h1 = h1.dup
    h2 = h2.dup
    h1.delete '.'
    h2.delete '.'
    return if top_r1 == top_r2
    svn_print_oldrev_line(top_r1, svn_rev_uri(viewer, top_r1), out)
    svn_print_newrev_line(top_r2, svn_rev_uri(viewer, top_r2), out)
    svn_path_sort(h1.keys|h2.keys).each {|f|
      r1, d1 = h1[f] || ['none', nil]
      r2, d2 = h2[f] || ['none', nil]
      next if r1 == r2 # no changes
      next if d1 == 'directory' && d2 == 'directory' # skip directory changes
      if d1 == 'file' && d2 == 'file' && r1 != 'none' && r2 != 'none'
        svn_print_chg_line(f, r1, r2,
          svn_diff_uri(viewer, f, top_r1, top_r2), out)
      else
        svn_print_del_line(f, r1,
          d1 == 'directory' ? svn_dir_uri(viewer, f, top_r1) :
			      svn_markup_uri(viewer, f, top_r1), out) if r1 != 'none'
        svn_print_add_line(f, r2,
          d2 == 'directory' ? svn_dir_uri(viewer, f, top_r2) :
			      svn_markup_uri(viewer, f, top_r2), out) if r2 != 'none'
      end
    }
  end

  def svn_print_oldrev_line(r, uri, out)
    line = "OLDREV #{r}"
    line << "\t" << uri.to_s if uri
    out.puts line
  end

  def svn_print_newrev_line(r, uri, out)
    line = "NEWREV #{r}"
    line << "\t" << uri.to_s if uri
    out.puts line
  end

  def svn_print_chg_line(f, r1, r2, uri, out)
    line = "CHG #{f}\t#{r1}->#{r2}"
    line << "\t" << uri.to_s if uri
    out.puts line
  end

  def svn_print_del_line(f, r, uri, out)
    line = "DEL #{f}\t#{r}->none"
    line << "\t" << uri.to_s if uri
    out.puts line
  end

  def svn_print_add_line(f, r, uri, out)
    line = "ADD #{f}\tnone->#{r}"
    line << "\t" << uri.to_s if uri
    out.puts line
  end

end

# segment       = *pchar
# pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
# unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
# pct-encoded   = "%" HEXDIG HEXDIG
# sub-delims    = "!" / "$" / "&" / "'" / "(" / ")"
#               / "*" / "+" / "," / ";" / "="
segment_regexp = '(?:[A-Za-z0-9\-._~!$&\'()*+,;=:@]|%[0-9A-Fa-f][0-9A-Fa-f])*'

ChkBuild.define_file_changes_viewer('svn',
  %r{\Ahttp://svn\.apache\.org/repos/asf (#{segment_regexp}(/#{segment_regexp})*)?\z}o) {
  |match, reptype, pat, checkout_line|
  # http://svn.apache.org/repos/asf
  # http://svn.apache.org/viewvc/?diff_format=u

  mod = match[1]
  mod = nil if mod && mod.empty?
  ChkBuild::ViewVC.new('http://svn.apache.org/viewvc/?diff_format=u', false, mod)
}

ChkBuild.define_title_hook(nil, %r{\Asvn/}) {|title, logs|
  logs.each {|log|
    next unless url = /^URL: (\S+)$/.match(log)
    next unless lastrev = /^Last Changed Rev: (\d+)$/.match(log)
    title.update_hidden_title(url[1], lastrev[1])
  }
}

