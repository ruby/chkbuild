require 'chkbuild/cvs'

class ChkBuild::Build
  def gnu_savannah_cvs(proj, mod, branch, opts={})
    opts = opts.dup
    opts[:viewcvs] ||= "http://savannah.gnu.org/cgi-bin/viewcvs/#{proj}?diff_format=u"
    self.cvs(":pserver:anonymous@cvs.savannah.gnu.org:/sources/#{proj}", mod, branch, opts)
  end
end
