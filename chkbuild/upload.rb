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

  # azure storage
  #
  # == Usage
  # Add `ChkBuild.azure_upload_target` to sample/build-ruby
  #
  # == Environmental Variables
  # * AZURE_STORAGE_ACCOUNT
  # * AZURE_STORAGE_ACCESS_KEY

  def self.azure_upload_target
    ENV['AZURE_STORAGE_ACCOUNT'] ||= 'rubyci'
    raise 'no AZURE_STORAGE_ACCESS_KEY env' unless ENV['AZURE_STORAGE_ACCESS_KEY']
    require 'azure'
    require_relative 'azure-patch'
    service = Azure::BlobService.new
    service.with_filter do |req, _next|
      i = 0
      begin
        next _next.call
      rescue
        case $!
        when Errno::ETIMEDOUT
          if i < 3
            i += 1
            retry
          end
        end
        raise
      end
    end
    self.add_upload_hook {|depsuffixed_name|
      self.do_upload_azure(service, ChkBuild.nickname, depsuffixed_name)
    }
  end

  def self.do_upload_azure(service, container, branch)
    begin
      res, body = service.get_blob(container, "#{branch}/recent.ltsv")
      server_start_time = body[/\tstart_time:(\w+)/, 1]
    rescue Azure::Core::Http::HTTPError => e
      server_start_time = '00000000T000000Z'
      if e.type == 'ContainerNotFound'
        service.create_container(container, :public_access_level => 'container')
      end
    end
    puts "Azure: #{branch} start_time: #{server_start_time}"

    latest = IO.foreach("#{ChkBuild.public_top}/#{branch}/recent.ltsv") do |line|
       break line[/\tstart_time:(\w+)/, 1]
    end

    Dir.foreach("#{ChkBuild.public_top}/#{branch}/log") do |path|
      next unless path.end_with?('.gz')
      blobname = "#{branch}/log/#{path}"
      filepath = "#{ChkBuild.public_top}/#{blobname}"
      if (service.get_blob_metadata(container, blobname) rescue false)
        File.unlink filepath
        next
      end
      if azcp0(service, container, blobname, filepath) && !path.start_with?(latest)
        File.unlink filepath
      end
    end

    %w[current.txt last.html.gz recent.ltsv summary.html summary.txt
      last.html last.txt recent.html rss summary.ltsv].each do |fn|
      path = "#{branch}/#{fn}"
      azcp0(service, container, path, "#{ChkBuild.public_top}/#{path}")
    end
  end

  def self.azcp0(service, container, blobname, filepath)
    unless File.exist?(filepath)
      puts "file '#{filepath}' is not found"
      return false
    end
    options = {}

    case filepath
    when /\.txt\.gz\z/
      options[:content_type] = "text/plain"
      options[:content_encoding] = 'gzip'
    when /\.html\.gz\z/
      options[:content_type] = "text/html"
      options[:content_encoding] = 'gzip'
    when /\.(?:ltsv|txt)\z/
      options[:content_type] = "text/plain"
    when /\.html\z/
      options[:content_type] = "text/html"
    when /(?:\A|\/)rss\z/
      options[:content_type] = "application/rss+xml"
    else
      warn "no content_type is defined for #{filepath}"
    end
    open(filepath, 'rb') do |f|
      puts "uploading '#{filepath}'..."
      service.create_block_blob(container, blobname, f, options)
    end
    true
  end

  # S3
  #
  # == Usage
  # Add `ChkBuild.s3_upload_target` to sample/build-ruby
  #
  # == Environmental Variables
  #  :access_key_id => ENV['AWS_ACCESS_KEY_ID'],
  #  :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])

  def self.s3_upload_target
    return if ENV["DISABLE_S3_UPLOAD"] # for local test
    bucket_name = 'rubyci'
    region = 'ap-northeast-1'
    begin
      require 'aws-sdk'
      $RUBYCI_AWS_SDK = "aws-sdk"
    rescue LoadError
      require 'aws-sdk-s3'
      $RUBYCI_AWS_SDK = "aws-sdk-s3"
    end
    bucket = Aws::S3::Resource.new(region: region).bucket(bucket_name)
    self.add_upload_hook {|depsuffixed_name|
      self.do_upload_s3(bucket, depsuffixed_name)
    }
  end

  def self.do_upload_s3(bucket, branch)
    cmd = %w[/opt/csw/bin/zgrep gzgrep zgrep].find{|x|spawn(x, '-V', out: IO::NULL, err: IO::NULL) rescue nil}
    keep = []
    require 'open3'
    logdir = s3_localpath("#{branch}/log")
    res, _ = Open3.capture2('find', logdir, '-name', '*.fail.html.gz', '-exec', cmd,'-Hm1','placeholder_start','{}',';')
    res.each_line do |line|
      # 20150816T150308Z.fail.html.gz:      <!--placeholder_start-->NewerDiff<!--placeholder_end--> &gt;
      keep << line[logdir.size+1, 16]
    end
    puts"keep: #{keep}"

    now = Time.now
    Dir.foreach(logdir) do |filename|
      next unless filename.end_with?('.gz')
      path = "#{branch}/log/#{filename}"
      filepath = s3_localpath(path)
      if s3sync(bucket, path)
        # upload success
        if path.end_with?('.html.gz') &&
          IO.read(filepath, 1000).include?('placeholder_start')
          next
        end
        unless keep.include?(filename[0, 16])
          puts "remove: #{filename}"
          File.unlink filepath # temporaly don't remove logs
        end
      end
    end

    %w[current.txt last.html.gz recent.ltsv summary.html summary.txt
      last.html last.txt recent.html rss summary.ltsv].each do |fn|
      path = "#{branch}/#{fn}"
      s3sync(bucket, path)
    end

    lcovdir = s3_localpath("#{branch}/lcov")
    if File.directory?(lcovdir)
      prefix = s3_localpath("")
      Dir.glob(lcovdir + "/**/*", File::FNM_DOTMATCH).sort.each do |filepath|
        if File.file?(filepath) && filepath.start_with?(prefix)
	  path = filepath[prefix.size..-1]
	  s3sync(bucket, path)
        end
      end
    end
  end

  def self.s3_localpath(path)
    "#{ChkBuild.public_top}/#{path}"
  end

  def self.s3_remotepath(path)
    "#{ChkBuild.nickname}/#{path}"
  end

  def self.s3sync(bucket, path)
    blobname = s3_remotepath(path)
    filepath = s3_localpath(path)
    unless File.exist?(filepath)
      warn "file '#{filepath}' is not found"
      return false
    end

    options = {}
    case path
    when /\.txt\.gz\z/
      options[:content_type] = 'text/plain'
      options[:content_encoding] = 'gzip'
    when /\.html\.gz\z/
      options[:content_type] = 'text/html'
      options[:content_encoding] = 'gzip'
    when /\.(?:ltsv|txt)\z/
      options[:content_type] = 'text/plain'
    when /\.html\z/
      options[:content_type] = 'text/html'
    when /(?:\A|\/)rss\z/
      options[:content_type] = 'application/rss+xml'
    else
      warn "no content_type is defined for #{filepath}"
    end

    puts "uploading '#{filepath}' to #{blobname}..."
    bucket.object(blobname).upload_file(filepath, options)
    true
  end
end

if __FILE__ == $0
  require 'pathname'
  require_relative 'main'
  def ChkBuild.main; end
  load File.expand_path('../../start-build', __FILE__)

  Dir.foreach(ChkBuild.s3_localpath("")) do |depsuffixed_name|
    next if depsuffixed_name !~ /\A(?:cross)?ruby-/
    ChkBuild.run_upload_hooks(depsuffixed_name)
  end
end
