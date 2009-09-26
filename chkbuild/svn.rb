# Copyright (C) 2006,2007,2009 Tanaka Akira  <akr@fsij.org>
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

require 'fileutils'
require "uri"

module ChkBuild; end # for testing

class ChkBuild::ViewVC
  def initialize(uri, old=false)
    @uri = uri
    @old = old
  end

  def rev_uri(r)
    revision = @old ? 'rev' : 'revision'
    extend_uri("", [['view', 'rev'], [revision, r.to_s]]).to_s
  end

  def markup_uri(d, f, r)
    pathrev = @old ? 'rev' : 'pathrev'
    extend_uri("/#{d}/#{f}", [['view', 'markup'], [pathrev, r.to_s]]).to_s
  end

  def dir_uri(d, f, r)
    pathrev = @old ? 'rev' : 'pathrev'
    extend_uri("/#{d}/#{f}", [[pathrev, r.to_s]]).to_s
  end

  def diff_uri(d, f, r1, r2)
    pathrev = @old ? 'rev' : 'pathrev'
    extend_uri("/#{d}/#{f}", [
      ['p1', "#{d}/#{f}"],
      ['r1', r1.to_s],
      ['r2', r2.to_s],
      [pathrev, r2.to_s]]).to_s
  end

  def extend_uri(path, params)
    uri = URI.parse(@uri)
    uri.path = uri.path + Escape.uri_path(path).to_s
    query = Escape.html_form(params).to_s
    (uri.query || '').split(/[;&]/).each {|param| query << ';' << param }
    uri.query = query
    uri
  end
end

class ChkBuild::Build
  def svn(svnroot, rep_dir, working_dir, opts={})
    network_access {
      svn_internal(svnroot, rep_dir, working_dir, opts)
    }
  end

  def svn_internal(svnroot, rep_dir, working_dir, opts={})
    url = svnroot + '/' + rep_dir
    opts = opts.dup
    opts[:section] ||= 'svn'
    if opts[:viewvc]||opts[:viewcvs]
      viewvc = ChkBuild::ViewVC.new(opts[:viewvc]||opts[:viewcvs], opts[:viewcvs]!=nil)
    else
      viewvc = nil
    end
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
      if /\d+\s+(\d+)\s+\S+\s+(.+)/ =~ line
        rev = $1.to_i
        path = $2
        dir = File.directory?(path)
        path << '/' if dir && path != '.'
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
    viewvc.rev_uri(r)
  end

  def svn_markup_uri(viewvc, d, f, r)
    return nil if !viewvc
    viewvc.markup_uri(d, f, r)
  end

  def svn_dir_uri(viewvc, d, f, r)
    return nil if !viewvc
    viewvc.dir_uri(d, f, r)
  end

  def svn_diff_uri(viewvc, d, f, r1, r2)
    return nil if !viewvc
    viewvc.diff_uri(d, f, r1, r2)
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
