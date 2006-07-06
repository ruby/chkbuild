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

  def detect_sections
    ret = []
    @io.rewind
    pat = /\A#{Regexp.quote @mark} /
    @io.each {|line|
      if pat =~ line
        epos = @io.pos
        spos = epos - line.length
        secname = $'.chomp.sub(/#.*/, '').strip
        ret << [spos, secname]
      end
    }
    ret
  end

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

  def start_section(secname)
    @io.flush
    if 0 < @io.stat.size
      @io.seek(-1, IO::SEEK_END)
      if @io.read != "\n"
        @io.write "\n"
      end
    end
    spos = @io.pos
    @sections << [spos, secname.strip]
    #@io.write "#{@mark} #{secname} \# #{'*' * 1000} #{Time.now.iso8601} #{'*' * 1000}\n"
    @io.write "#{@mark} #{secname} \# #{Time.now.iso8601}\n"
  end

  def get_section(secname)
    @sections.each_index {|i|
      spos, sname = @sections[i]
      if sname == secname
        if i+1 < @sections.length
          epos = @sections[i+1][0]
        else
          epos = @io.stat.size
        end
        @io.seek spos
        line = @io.gets
        return @io.read(epos - spos - line.length)
      end
    }
    return nil
  end

  def get_all_log
    @io.rewind
    @io.read
  end
end
