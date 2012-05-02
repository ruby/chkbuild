# chkbuild/viewvc.rb - ViewVC support module
#
# Copyright (C) 2006-2012 Tanaka Akira  <akr@fsij.org>
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

require "uri"

module ChkBuild; end # for testing

class ChkBuild::ViewVC
  def self.find_viewvc_line(lines)
    viewvc = nil
    lines.each {|line|
      if /\AVIEWER\s+ViewVC\s+(\S+)/ =~ line
        viewvc = ChkBuild::ViewVC.new($1)
	break
      elsif /\AVIEWER\s+ViewCVS\s+(\S+)/ =~ line
        viewvc = ChkBuild::ViewVC.new($1, true)
	break
      end
    }
    viewvc
  end

  def initialize(uri, old=false)
    @uri = uri
    @old = old
  end
  attr_reader :uri, :old

  def rev_uri(r)
    revision = @old ? 'rev' : 'revision'
    extend_uri("", [['view', 'rev'], [revision, r.to_s]]).to_s
  end

  def markup_uri(d, f, r)
    pathrev = @old ? 'rev' : 'pathrev'
    extend_uri("/#{d}/#{f}", [['view', 'markup'], [pathrev, r.to_s]]).to_s
  end

  def dir_uri(d, f, r)
    pathrev = @old ? 'rev' : 'pathrev'
    extend_uri("/#{d}/#{f}", [[pathrev, r.to_s]]).to_s
  end

  def diff_uri(d, f, r1, r2)
    pathrev = @old ? 'rev' : 'pathrev'
    extend_uri("/#{d}/#{f}", [
      ['p1', "#{d}/#{f}"],
      ['r1', r1.to_s],
      ['r2', r2.to_s],
      [pathrev, r2.to_s]]).to_s
  end

  def extend_uri(path, params)
    uri = URI.parse(@uri)
    uri.path = uri.path + Escape.uri_path(path).to_s
    params = params.dup
    query = Escape.html_form(params).to_s
    (uri.query || '').split(/[;&]/).each {|param| query << '&' << param }
    uri.query = query
    uri
  end
end
