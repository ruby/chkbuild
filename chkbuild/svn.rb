require 'fileutils'

class ChkBuild::Build
  def svn(url, working_dir, opts={})
    opts = opts.dup
    opts[:section] ||= 'svn'
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.svn")
      Dir.chdir(working_dir) {
        self.run "svn", "cleanup", opts
        opts[:section] = nil
        self.run "svn", "update", opts
      }
    else
      if File.exist?(working_dir)
        FileUtils.rm_rf(working_dir)
      end
      self.run "svn", "checkout", url, working_dir, opts
    end
  end
end
