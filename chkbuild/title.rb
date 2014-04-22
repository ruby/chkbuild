# chkbuild/title.rb - title class implementation
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

require 'util'

class ChkBuild::Title
  def initialize(target, logfile)
    @target = target
    @logfile = logfile
    @title = {}
    @title[:version] = @logfile.suffixed_name
    @title[:dep_versions] = []
    @title[:hostname] = "(#{ChkBuild.nickname})"
    @title_order = [:version, :dep_versions, :hostname, :warn, :mark, :status]
    @logfile.each_secname {|secname|
      if @logfile.failed_section?(secname)
	log = @logfile.get_section(secname)
	lastline = log.chomp("").lastline
	sym = "failure_#{secname}".intern
	if %r{/} =~ secname && lastline == "failed(#{secname})"
	  lastline = "failed(#{secname.sub(%r{/.*\z}, '/')})"
	end
	@title_order << sym
	@title[sym] = lastline
      end
    }
  end
  attr_reader :logfile

  def version
    return @title[:version]
  end

  def depsuffixed_name() @logfile.depsuffixed_name end
  def suffixed_name() @logfile.suffixed_name end
  def target_name() @logfile.target_name end
  def suffixes() @logfile.suffixes end

  def run_hooks
    run_title_hooks
    run_failure_hooks
  end

  def run_title_hooks
    ChkBuild.fetch_title_hook(@target.target_name).each {|secname, block|
      if secname == nil
        block.call self, @logfile
      elsif Array === secname
        log = []
        secname.each {|sn|
          log << @logfile.get_section(sn)
        }
        block.call self, log
      elsif Regexp === secname
        log = []
        @logfile.secnames.each {|sn|
          next if secname !~ sn
          log << @logfile.get_section(sn)
        }
        block.call self, log
      elsif log = @logfile.get_section(secname)
        block.call self, log
      end
    }
  end

  def run_failure_hooks
    ChkBuild.fetch_failure_hook(@target.target_name).each {|secname, block|
      if @logfile.failed_section?(secname)
        log = @logfile.get_section(secname)
	sym = "failure_#{secname}".intern
	if newval = block.call(log)
	  @title[sym] = newval
	end
      end
    }
  end

  def update_title(key, val=nil)
    if val == nil && block_given?
      val = yield @title[key]
      return if !val
    end
    @title[key] = val
    unless @title_order.include? key
      @title_order[-1,0] = [key]
    end
  end

  def update_hidden_title(key, val=nil)
    @title_order.delete key
    if val == nil && block_given?
      val = yield @title[key]
      return if !val
    end
    @title[key] = val
  end

  def make_title
    title_hash = @title
    a = []
    a = @title_order.map {|key|
      title_hash[key]
    }.flatten.compact
    h = Hash.new(0)
    a.each {|s|
      h[s] += 1
    }
    a2 = []
    a.each {|s|
      if h[s] == 1
        a2 << s
      elsif h[s] > 1
	n = h[s]
        if /\A[0-9]/ =~ s
	  a2 << "#{n}_#{s}"
	else
	  a2 << "#{n}#{s}"
	end
	h[s] = 0
      end
    }
    a2.join(' ').gsub(/\s+/, ' ').strip
  end

  def [](key)
    @title[key]
  end

  def keys
    @title_order
  end

  def hidden_keys
    @title.keys - @title_order
  end
end
