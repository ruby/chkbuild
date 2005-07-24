module SSH
  HOME_DIRECTORY = Etc.getpwuid.dir

  module_function
  def add_known_host(arg)
    case arg
    when Array
      arg.each {|a| add_ssh_known_host(a) }
    when String
      hostnames, type, key_rest = arg.split(/\s+/, 3)
      hostnames = hostnames.split(/,/)
      begin
        Dir.mkdir("#{HOME_DIRECTORY}/.ssh", 0700)
      rescue Errno::EEXIST
      end
      open("#{HOME_DIRECTORY}/.ssh/known_hosts", File::RDWR|File::CREAT) {|f|
        f.each_line {|line|
          hs, t, kr = line.split(/\s+/, 3)
          next if t != type
          hs = hs.split(/,/)
          if !(hs & hostnames).empty?
            return
          end
        }
        f.puts arg
      }
    else
      raise "unexpected argument: #{arg.inspect}"
    end
  end
end

