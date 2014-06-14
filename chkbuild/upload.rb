# chkbuild/upload.rb - upload method definition
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

module ChkBuild
  @upload_hook = []

  def self.add_upload_hook(&block)
    @upload_hook << block
  end

  def self.run_upload_hooks(depsuffixed_name)
    @upload_hook.reverse_each {|block|
      begin
        block.call depsuffixed_name
      rescue Exception
        p $!
      end
    }
  end

  # rsync/ssh

  def self.rsync_ssh_upload_target(rsync_target, private_key=nil)
    self.add_upload_hook {|depsuffixed_name|
      self.do_upload_rsync_ssh(rsync_target, private_key, depsuffixed_name)
    }
  end

  def self.do_upload_rsync_ssh(rsync_target, private_key, depsuffixed_name)
    if %r{\A(?:([^@:]+)@)([^:]+)::(.*)\z} !~ rsync_target
      raise "invalid rsync target: #{rsync_target.inspect}"
    end
    remote_user = $1 || ENV['USER'] || Etc.getpwuid.name
    remote_host = $2
    remote_path = $3
    local_host = Socket.gethostname
    private_key ||= "#{ENV['HOME']}/.ssh/chkbuild-#{local_host}-#{remote_host}"

    begin
      save = ENV['SSH_AUTH_SOCK']
      ENV['SSH_AUTH_SOCK'] = nil
      system "rsync", "--delete", "-rte", "ssh -akxi #{private_key}", "#{ChkBuild.public_top}/#{depsuffixed_name}", "#{rsync_target}"
    ensure
      ENV['SSH_AUTH_SOCK'] = save
    end
  end
end
