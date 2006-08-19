require "uri"

class ChkBuild::Build
  def cvs(cvsroot, mod, branch, opts={})
    opts = opts.dup
    opts[:section] ||= 'cvs'
    working_dir = opts.fetch(:working_dir, mod)
    if !File.exist? "#{ENV['HOME']}/.cvspass"
      opts['ENV:CVS_PASSFILE'] = '/dev/null' # avoid warning
    end
    if File.directory?(working_dir)
      Dir.chdir(working_dir) {
        h1 = cvs_revisions
        self.run("cvs", "-f", "-z3", "-Q", "update", "-kb", "-dP", opts)
        h2 = cvs_revisions
        cvs_print_revisions(h1, h2, opts[:viewvc]||opts[:viewcvs]||opts[:cvsweb])
      }
    else
      h1 = nil
      if File.identical?(@build_dir, '.') &&
         !(ts = build_time_sequence - [@start_time]).empty? &&
         File.directory?(old_working_dir = "#{@target_dir}/#{ts.last}/#{working_dir}")
        Dir.chdir(old_working_dir) {
          h1 = cvs_revisions
        }
      end
      if branch
        self.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-kb", "-d", working_dir, "-Pr", branch, mod, opts)
      else
        self.run("cvs", "-f", "-z3", "-Qd", cvsroot, "co", "-kb", "-d", working_dir, "-P", mod, opts)
      end
      Dir.chdir(working_dir) {
        h2 = cvs_revisions
        cvs_print_revisions(h1, h2, opts[:viewvc]||opts[:viewcvs]||opts[:cvsweb])
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
    path << "/" << Escape.uri_path(repository) if repository != '.'
    path << "/" << Escape.uri_path(filename)
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

  def cvs_print_changes(h1, h2, viewcvs=nil)
    (h1.keys | h2.keys).sort.each {|k|
      f = k.flatten.join('/')
      cvsroot1, repository1, r1 = h1[k] || [nil, nil, 'none']
      cvsroot2, repository2, r2 = h2[k] || [nil, nil, 'none']
      if r1 != r2
        if r1 == 'none'
          line = "ADD"
        elsif r2 == 'none'
          line = "DEL"
        else
          line = "CHG"
        end
        line << " #{f}\t#{r1}->#{r2}"
        if viewcvs
          line << "\t" << cvs_uri(viewcvs, repository1 || repository2, k[1], r1, r2)
        end
        puts line
      end
    }
  end

  def cvs_print_revisions(h1, h2, viewcvs=nil)
    cvs_print_changes(h1, h2, viewcvs) if h1
    puts 'revisions:'
    h2.keys.sort.each {|k|
      f = k.flatten.join('/')
      cvsroot2, repository2, r2 = h2[k] || [nil, nil, 'none']
      digest = sha256_digest_file(f)
      puts "#{f}\t#{r2}\t#{digest}"
    }
  end
end
