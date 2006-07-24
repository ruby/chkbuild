require 'time'

class IO
  def tmp_reopen(io)
    save = self.dup
    begin
      self.reopen(io)
      begin
        yield
      ensure
        self.reopen(save)
      end
    ensure
      save.close
    end
  end
end

class LogFile
  InitialMark = '=='

  def initialize(filename)
    @filename = filename
    @io = File.open(filename, File::RDWR|File::CREAT|File::APPEND)
    @io.sync = true
    @mark = read_separator
    @sections = detect_sections
  end

  def read_separator
    mark = nil
    if @io.stat.size != 0
      @io.rewind
      mark = @io.gets[/\A\S+/]
    end
    mark || InitialMark
  end
  private :read_separator

  def detect_sections
    ret = {}
    @io.rewind
    pat = /\A#{Regexp.quote @mark} /
    @io.each {|line|
      if pat =~ line
        epos = @io.pos
        spos = epos - line.length
        secname = $'.chomp.sub(/#.*/, '').strip
        ret[secname] = spos
      end
    }
    ret
  end
  private :detect_sections

  # logfile.with_default_output { ... }
  def with_default_output
    File.open(@filename, File::WRONLY|File::APPEND) {|f|
      STDERR.tmp_reopen(f) {
        STDERR.sync = true
        STDOUT.tmp_reopen(f) {
          STDOUT.sync = true
          yield
        }
      }
    }
  end

  def change_default_output
    STDOUT.reopen(@save_io = File.for_fd(@io.fileno, File::WRONLY|File::APPEND))
    STDERR.reopen(STDOUT)
    STDOUT.sync = true
    STDERR.sync = true
  end

  # start_section returns the (unique) section name.
  def start_section(secname)
    @io.flush
    if 0 < @io.stat.size
      @io.seek(-1, IO::SEEK_END)
      if @io.read != "\n"
        @io.write "\n"
      end
    end
    spos = @io.pos
    secname = secname.strip
    if @sections[secname]
      i = 2
      while @sections["#{secname} (#{i})"]
        i += 1
      end
      secname = "#{secname} (#{i})"
    end
    @sections[secname] = spos
    @io.write "#{@mark} #{secname} \# #{Time.now.iso8601}\n"
    secname
  end

  def get_section(secname)
    spos = @sections[secname]
    return nil if !spos
    @io.seek spos
    @io.gets("\n#{@mark} ").chomp("#{@mark} ").sub(/\A.*\n/, '')
  end

  def get_all_log
    @io.rewind
    @io.read
  end

  def modify_section(secname, data)
    spos = @sections[secname]
    raise ArgumentError, "no section: #{secname.inspect}" if !spos
    data += "\n" if /\n\z/ !~ data
    old = nil
    File.open(@filename, File::RDWR) {|f|
      f.seek spos
      rest = f.read
      if /\n#{Regexp.quote @mark} / =~ rest
        epos = $~.begin(0) + 1
        curr = rest[0...epos]
        rest = rest[epos..-1]
      else
        curr = rest
        rest = ''
      end
      if /\n/ =~ curr
        secline = $` + $&
        old = $'
      else
        secline = curr + "\n"
        old = ''
      end
      f.seek spos
      f.print secline, data, rest
      f.flush
      f.truncate(f.pos)
    }
    off = data.length - old.length
    @sections.each_pair {|n, pos|
      if spos < pos
        @sections[n] = pos + off
      end
    }
    nil
  end
end
