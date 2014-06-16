# chkbuild/cvs.rb - cvs access method
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

class ChkBuild::IBuild
  def cvs(cvsroot, mod, branch, opts={})
    network_access {
      cvs_internal(cvsroot, mod, branch, opts)
    }
  end

  def cvs_internal(cvsroot, mod, branch, opts={})
    opts = opts.dup
    opts[:section] ||= 'cvs'
    working_dir = opts.fetch(:working_dir, mod)
    if !File.exist? "#{ENV['HOME']}/.cvspass"
      opts['ENV:CVS_PASSFILE'] = '/dev/null' # avoid warning
    end
    if File.directory?(working_dir)
      Dir.chdir(working_dir) {
	cvs_logfile(opts) {|outio, errio, opts2|
	  opts2[:output_interval_file_list] = [STDOUT, STDERR, outio, errio]
	  self.run("cvs", "-f", "-z3", "update", "-kb", "-dP", opts2)
	}
        h2 = cvs_revisions
        cvs_print_revisions(cvsroot, mod, branch, h2)
      }
    else
      if branch
	command = ["cvs", "-f", "-z3", "-d", cvsroot, "co", "-kb", "-d", working_dir, "-P", "-r", branch, mod]
      else
        command = ["cvs", "-f", "-z3", "-d", cvsroot, "co", "-kb", "-d", working_dir, "-P", mod]
      end
      cvs_logfile(opts) {|outio, errio, opts2|
	opts2[:output_interval_file_list] = [STDOUT, STDERR, outio, errio]
	command << opts2
	self.run(*command)
      }
      Dir.chdir(working_dir) {
        h2 = cvs_revisions
        cvs_print_revisions(cvsroot, mod, branch, h2)
      }
    end
  end

  def cvs_revisions
    h = {}
    Dir.glob("**/CVS").each {|cvs_dir|
      cvsroot = IO.read("#{cvs_dir}/Root").chomp
      repository = IO.read("#{cvs_dir}/Repository").chomp
      ds = cvs_dir.split(%r{/})[0...-1]
      IO.foreach("#{cvs_dir}/Entries") {|line|
        h[[ds, $1]] = [cvsroot, repository, $2] if %r{^/([^/]+)/([^/]*)/} =~ line
      }
    }
    h
  end

  def cvs_uri(viewcvs, repository, filename, r1, r2)
    uri = URI.parse(viewcvs)
    path = uri.path.dup
    path << "/" << Escape.uri_path(repository).to_s if repository != '.'
    path << "/" << Escape.uri_path(filename).to_s
    uri.path = path
    query = (uri.query || '').split(/[;&]/)
    if r1 == 'none'
      query << "rev=#{r2}"
    elsif r2 == 'none'
      query << "rev=#{r1}"
    else
      query << "r1=#{r1}" << "r2=#{r2}"
    end
    uri.query = query.join(';')
    uri.to_s
  end

  def cvs_print_revisions(cvsroot, mod, branch, h2)
    puts "CHECKOUT cvs #{cvsroot} #{mod} #{branch || ''}"
    h2.keys.sort.each {|k|
      f = k.flatten.join('/')
      _cvsroot2, _repository2, r2 = h2[k] || [nil, nil, 'none']
      digest = sha256_digest_file(f)
      puts "FILE #{f}\t#{r2}\t#{digest}"
    }
  end

  def cvs_logfile(opts)
    with_templog(self.build_dir, "cvs.out.") {|outfile, outio|
      with_templog(self.build_dir, "cvs.err.") {|errfile, errio|
	opts2 = opts.dup
	opts2[:stdout] = outfile
	opts2[:stderr] = errfile
	begin
	  yield outio, errio, opts2
	ensure
	  outio.rewind
	  outio.each_line {|line| puts "CVSOUT #{line}" }
	  errio.rewind
	  errio.each_line {|line| puts "CVSERR #{line}" }
	end
      }
    }
  end
end

class ChkBuild::IFormat
  def output_cvs_change_lines(checkout_line, lines1, lines2, out)
    if /CHECKOUT cvs (\S+) (\S+) (\S*)\n/ !~ checkout_line
      out.puts "unexpected checkout line: #{checkout_line}"
      return
    end
    cvsroot = $1
    mod = $2
    branch = $3
    branch = nil if branch.empty?
    viewer = ChkBuild.find_file_changes_viewer('cvs', "#{cvsroot} #{mod}")
    h1 = cvs_restore_file_info(lines1)
    h2 = cvs_restore_file_info(lines2)
    cvs_print_changes(mod, h1, h2, viewer, out)
  end

  def cvs_restore_file_info(lines)
    h = {}
    lines.each {|line|
      case line
      when /\AFILE (\S+)\t(\S+)/
	h[$1] = $2
      end
    }
    h
  end

  def cvs_print_changes(mod, h1, h2, viewer, out)
    (h1.keys | h2.keys).sort.each {|f|
      r1 = h1[f] || 'none'
      r2 = h2[f] || 'none'
      if r1 != r2
        if r1 == 'none'
          line = "ADD"
        elsif r2 == 'none'
          line = "DEL"
        else
          line = "CHG"
        end
        line << " #{f}\t#{r1}->#{r2}"
        if viewer
	  if r1 == 'none'
	    uri = viewer.markup_uri(nil, f, r2)
	  elsif r2 == 'none'
	    uri = viewer.markup_uri(nil, f, r1)
	  else
	    uri = viewer.diff_uri(nil, f, r1, r2)
	  end
	  line << "\t" << uri
        end
        out.puts line
      end
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

ChkBuild.define_file_changes_viewer('cvs',
  %r{\A:pserver:anonymous@puszcza\.gnu\.org\.ua:/cvsroot/(#{segment_regexp}) (#{segment_regexp}(/#{segment_regexp})*)?\z}o) {
  |match, reptype, pat, checkout_line|
  # :pserver:anonymous@puszcza.gnu.org.ua:/cvsroot/gdbm gdbm
  # http://puszcza.gnu.org.ua/viewvc/gdbm/

  project = match[1]
  mod = match[2]
  ChkBuild::ViewVC.new("http://puszcza.gnu.org.ua/viewvc/#{project}/?diff_format=u", false, mod)
}

