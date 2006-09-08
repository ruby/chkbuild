require 'find'
require 'tempfile'

require 'escape'

module GDB
  module_function

  def check_core(dir)
    binaries = {}
    core_info = []
    Find.find(dir.to_s) {|f|
      stat = File.stat(f)
      basename = File.basename(f)
      binaries[basename] = f if stat.file? && stat.executable?
      next if /\bcore\b/ !~ basename
      next if /\.chkbuild\.\d+\z/ =~ basename
      guess = `file #{f}`
      next if /\bcore\b.*from '(.*?)'/ !~ guess.sub(/\A.*?:/, '')
      core_info << [f, $1]
    }
    gdb_command = nil
    core_info.each {|core_path, binary|
      next unless binary_path = binaries[binary]
      core_path = rename_core(core_path)
      unless gdb_command
        gdb_command = Tempfile.new("gdb-bt")
        gdb_command.puts "bt"
        gdb_command.close
      end
      puts
      puts "binary: #{binary_path}"
      puts "core: #{core_path}"
      gdb_output = `gdb -batch -n -x #{Escape.shell_escape gdb_command.path} #{Escape.shell_escape binary_path} #{Escape.shell_escape core_path}`
      puts gdb_output
      puts "gdb status: #{$?}"
    }
  end

  def rename_core(core_path)
    suffix = ".chkbuild."
    n = 1
    while File.exist?(new_path = "#{core_path}.chkbuild.#{n}")
      n += 1
    end
    File.rename(core_path, new_path)
    new_path
  end
end
