module SSH
  HOME_DIRECTORY = Etc.getpwuid.dir

  module_function
  def add_known_host(arg)
    case arg
    when Array
      arg.each {|a| add_ssh_known_host(a) }
    when String
      host = arg[/\A[^ ,]+/]
      begin
        Dir.mkdir("#{HOME_DIRECTORY}/.ssh", 0700)
      rescue Errno::EEXIST
      end
      open("#{HOME_DIRECTORY}/.ssh/known_hosts", File::RDWR|File::CREAT) {|f|
        f.each_line {|line|
          line[/\A[^ ]+/].scan(/[^,]+/) {|h|
            return if h == host
          }
        }
        f.puts arg
      }
    else
      raise "unexpected argument: #{arg.inspect}"
    end
  end
end

