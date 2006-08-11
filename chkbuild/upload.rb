module ChkBuild
  @upload_hook = []

  def self.add_upload_hook(&block)
    @upload_hook << block
  end

  def self.run_upload_hooks(suffixed_name)
    @upload_hook.reverse_each {|block|
      begin
        block.call suffixed_name
      rescue Exception
        p $!
      end
    }
  end

  # rsync/ssh

  def self.rsync_ssh_upload_target(rsync_target, private_key=nil)
    self.add_upload_hook {|name|
      self.do_upload_rsync_ssh(rsync_target, private_key, name)
    }
  end

  def self.do_upload_rsync_ssh(rsync_target, private_key, name)
    if %r{\A(?:([^@:]+)@)([^:]+)::(.*)\z} !~ rsync_target
      raise "invalid rsync target: #{rsync_target.inspect}"
    end
    remote_user = $1 || ENV['USER'] || Etc.getpwuid.name
    remote_host = $2
    remote_path = $3
    local_host = Socket.gethostname
    private_key ||= "#{ENV['HOME']}/.ssh/chkbuild-#{local_host}-#{remote_host}"

    pid = fork {
      ENV.delete 'SSH_AUTH_SOCK'
      exec "rsync", "--delete", "-rte", "ssh -akxi #{private_key}", "#{ChkBuild.public_top}/#{name}", "#{rsync_target}"
    }
    Process.wait pid
  end
end
