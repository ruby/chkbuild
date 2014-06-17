# chkbuild/logfile.rb - chkbuild's log file library
#
# Copyright (C) 2006-2011 Tanaka Akira  <akr@fsij.org>
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

module ChkBuild
end

class ChkBuild::LogFile
  InitialMark = '=='

  def self.os_version
    if File.readable?("/etc/debian_version")
      ver = File.read("/etc/debian_version").chomp
      case ver
      when /\A2\.0/; codename = 'potato'
      when /\A3\.0/; codename = 'woody'
      when /\A3\.1/; codename = 'sarge'
      when /\A4\.0/; codename = 'etch'
      when /\A5\.0/; codename = 'lenny'
      when /\A6\.0/; codename = 'squeeze'
      when /\A7\.0/; codename = 'wheezy'
      else codename = nil
      end
      rel = ''
      rel << "Distributor ID:\tDebian\n"
      rel << "Description:\tDebian GNU/Linux #{ver}"
      rel << " (#{codename})" if codename
      rel << "\n"
      rel << "Release:\t#{ver}\n"
      rel << "Codename:\t#{codename}\n" if codename
      return rel
    end
    nil
  end

  def self.capture_stdout(command)
    out = `exec 2>/dev/null; #{command}` rescue nil
    return out if $?.success?
    nil
  end

  def self.show_os_version(logfile)
    puts "Nickname: #{ChkBuild.nickname}"
    logfile.start_section 'uname'
    uname =   capture_stdout('uname -srvm'); puts "uname_srvm: #{uname}" if uname
    uname_s = capture_stdout('uname -s'); puts "uname_s: #{uname_s}" if uname_s # POSIX
    uname_r = capture_stdout('uname -r'); puts "uname_r: #{uname_r}" if uname_r # POSIX
    uname_v = capture_stdout('uname -v'); puts "uname_v: #{uname_v}" if uname_v # POSIX
    uname_m = capture_stdout('uname -m'); puts "uname_m: #{uname_m}" if uname_m # POSIX
    uname_p = capture_stdout('uname -p'); puts "uname_p: #{uname_p}" if uname_p # GNU/Linux, FreeBSD, NetBSD, OpenBSD, SunOS
    uname_i = capture_stdout('uname -i'); puts "uname_i: #{uname_i}" if uname_i # GNU/Linux, FreeBSD, SunOS
    uname_o = capture_stdout('uname -o'); puts "uname_o: #{uname_o}" if uname_o # GNU/Linux, FreeBSD, SunOS

    [
      "/etc/debian_version",
      "/etc/redhat-release",
      "/etc/gentoo-release",
      "/etc/slackware-version",
      "/etc/system-release", # Fedora, Amazon Linux
      "/etc/os-release", # systemd, http://0pointer.de/blog/projects/os-release.html
    ].each {|filename|
      if File.file? filename
        logfile.start_section filename
        contents = File.read filename
        puts contents
      end
    }

    debian_arch = capture_stdout('dpkg --print-architecture')
    if debian_arch
      logfile.start_section 'dpkg'
      puts "architecture: #{debian_arch}"
    end

    lsb_release = capture_stdout("lsb_release -idrc") # recent GNU/Linux
    if lsb_release
      logfile.start_section 'lsb_release'
      puts lsb_release
    else
      os_ver = self.os_version
      if os_ver
        logfile.start_section 'lsb_release(emu)'
        puts os_ver
      end
    end

    eselect_profile = capture_stdout('eselect --brief profile show') # Gentoo
    if eselect_profile
      logfile.start_section 'eselect_profile'
      puts eselect_profile.strip
    end

    sw_vers = capture_stdout('sw_vers') # Mac OS X
    if sw_vers
      logfile.start_section 'sw_vers'
      puts sw_vers
    end

    oslevel = capture_stdout('oslevel') # AIX
    if oslevel
      logfile.start_section 'oslevel'
      puts "oslevel: #{oslevel}"
      oslevel_s = capture_stdout('oslevel -s')
      puts "oslevel_s: #{oslevel_s}" if oslevel_s
    end

    if /SunOS/ =~ uname_s
      begin
        etc_release = File.read("/etc/release")
        first_line = etc_release[/\A.*/].strip
      rescue
      end
      if first_line && !first_line.empty?
        logfile.start_section '/etc/release'
        puts first_line
      end
    end
  end

  def self.write_open(filename, build)
    logfile = self.new(filename, true)
    logfile.start_section build.depsuffixed_name
    logfile.with_default_output {
      self.show_os_version(logfile)
      section_started = false
      build.traverse_depbuild {|depbuild|
        next if build == depbuild
        if !section_started
          logfile.start_section 'dependencies'
          section_started = true
        end
        puts "#{depbuild.suffixed_name} #{depbuild.start_time}"
      }
    }
    logfile
  end

  def self.append_open(filename)
    self.new(filename, true)
  end

  def dependencies
    return [] unless log = self.get_section('dependencies')
    r = []
    log.each_line {|line|
      if /^(\S+) (\d+T\d+Z?) \((.*)\)$/ =~ line
        r << [$1, $2, $3]
      elsif /^(\S+) (\d+T\d+Z?)$/ =~ line
        r << [$1, $2, $1]
      end
    }
    r
  end

  def depsuffixed_name
    return @depsuffixed_name if defined? @depsuffixed_name
    if /\A\S+\s+(\S+)/ =~ self.get_all_log
      return @depsuffixed_name = $1
    end
    raise "unexpected log format"
  end

  def suffixed_name() depsuffixed_name.sub(/_.*/, '') end
  def target_name() suffixed_name.sub(/-.*/, '') end
  def suffixes() suffixed_name.split(/-/)[1..-1] end

  def self.failed_line?(line)
    if /\Afailed\(.*\)\z/ =~ line.chomp
      true
    else
      false
    end
  end

  def failed_section?(secname)
    if log = get_section(secname)
      lastline = log.chomp("").lastline
      if ChkBuild::LogFile.failed_line?(lastline)
        return true
      end
    end
    false
  end

  def self.read_open(filename)
    self.new(filename, false)
  end

  def initialize(filename, writemode)
    @writemode = writemode
    mode = writemode ? File::RDWR|File::CREAT|File::APPEND : File::RDONLY
    @filename = filename
    @io = File.open(filename, mode)
    @io.set_encoding("ascii-8bit") if @io.respond_to? :set_encoding
    @io.sync = true
    @mark = read_separator
    @sections = detect_sections
  end
  attr_reader :filename

  def read_separator
    mark = nil
    if @io.stat.size != 0
      @io.rewind
      mark = @io.gets[/\A\S+/]
    end
    mark || InitialMark
  end
  private :read_separator

  def self.parse_section_header(line)
    line.split(/\s+/, 3)
  end

  def detect_sections
    ret = {}
    @io.rewind
    pat = /\A#{Regexp.quote @mark} /
    @io.each {|line|
      if pat =~ line
        epos = @io.pos
        spos = epos - line.length
        _, secname, _rest = self.class.parse_section_header(line)
        ret[secname] = spos
      end
    }
    ret
  end
  private :detect_sections

  # logfile.with_default_output { ... }
  def with_default_output
    raise "not opened for writing" if !@writemode
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
    raise "not opened for writing" if !@writemode
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
      while @sections["#{secname}(#{i})"]
        i += 1
      end
      secname = "#{secname}(#{i})"
    end
    @sections[secname] = spos
    @io.write "#{@mark} #{secname} \# #{Time.now.iso8601}\n"
    secname
  end

  def secnames
    @sections.keys.sort_by {|secname| @sections[secname] }
  end

  def each_secname(&block)
    @sections.keys.sort_by {|secname| @sections[secname] }.each(&block)
  end

  def section_size(secname)
    spos = @sections[secname]
    raise ArgumentError, "no section : #{secname.inspect}" if !spos
    epos = @sections.values.reject {|pos| pos <= spos }.min
    epos = @io.stat.size if !epos
    epos - spos
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

  def each_line(&block)
    @io.rewind
    @io.each_line(&block)
  end

  def self.each_log_line(io)
    firstline = io.gets
    firstline.force_encoding("ascii-8bit") if firstline.respond_to? :force_encoding
    return if !firstline
    yield :header, firstline
    mark = firstline[/\A\S+/]
    pat = /\A#{Regexp.quote mark} /
    io.each {|line|
      line.force_encoding("ascii-8bit") if line.respond_to? :force_encoding
      if pat =~ line
        yield :header, line
      elsif /\Afailed\(.*\)\z/ =~ line.chomp
        yield :fail, line
      else
        yield :log, line
      end
    }
  end

  def each_log_line(&block)
    @io.rewind
    self.class.each_log_line(@io, &block)
  end
end
