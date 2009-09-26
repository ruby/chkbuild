# Copyright (C) 2006,2009 Tanaka Akira  <akr@fsij.org>
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#  3. The name of the author may not be used to endorse or promote products
#     derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
# OF SUCH DAMAGE.

require 'util'

class String
  def lastline
    if pos = rindex(?\n)
      self[(pos+1)..-1]
    else
      self
    end
  end
end

class ChkBuild::Title
  def initialize(target, logfile)
    @target = target
    @logfile = logfile
    @title = {}
    @title[:version] = @logfile.suffixed_name
    @title[:dep_versions] = []
    @title[:hostname] = "(#{Util.simple_hostname})"
    @title_order = [:version, :dep_versions, :hostname, :warn, :mark, :status]
    @logfile.each_secname {|secname|
      log = @logfile.get_section(secname)
      lastline = log.chomp("").lastline
      if /\Afailed\(.*\)\z/ =~ lastline
        sym = "failure_#{secname}".intern
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
    @target.each_title_hook {|secname, block|
      if secname == nil
        block.call self, @logfile.get_all_log
      elsif log = @logfile.get_section(secname)
        block.call self, log
      end
    }
  end

  def run_failure_hooks
    @target.each_failure_hook {|secname, block|
      if log = @logfile.get_section(secname)
        lastline = log.chomp("").lastline
        if /\Afailed\(.*\)\z/ =~ lastline
          sym = "failure_#{secname}".intern
          if newval = block.call(log)
            @title[sym] = newval
          end
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

  def make_title
    title_hash = @title
    @title_order.map {|key|
      title_hash[key]
    }.flatten.join(' ').gsub(/\s+/, ' ').strip
  end

  def [](key)
    @title[key]
  end
end
