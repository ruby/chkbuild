# chkbuild/options.rb - build option implementation
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
  @default_options = {
    :num_oldbuilds => 1,
    :limit_core => :unlimited,
    :limit_cpu => nil,
    :limit_stack => nil,
    :limit_data => nil,
    :limit_as => nil,
    :output_line_max => 1024 * 10 # Test periodically.  Not rigorous.
  }

  def self.get_options
    @default_options.dup
  end

  def self.num_oldbuilds
    @default_options[:num_oldbuilds]
  end
  def self.num_oldbuilds=(val)
    @default_options[:num_oldbuilds] = val
  end

  def self.limit(hash)
    hash.each {|k, v|
      s = "limit_#{k}".intern
      raise "unexpected resource name: #{k}" if !@default_options.has_key?(s)
      @default_options[s] = v
    }
  end

  def self.get_limit
    ret = {}
    @default_options.each {|k, v|
      next if /\Alimit_/ !~ k.to_s
      next if !v
      s = $'.intern
      ret[s] = v
    }
    ret
  end

  def self.nice=(n)
    @default_options[:nice] = n
  end
end
