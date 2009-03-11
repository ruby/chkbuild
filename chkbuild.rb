Encoding.default_external = "ASCII-8BIT" if defined?(Encoding.default_external = nil)

require 'chkbuild/main'
require 'chkbuild/lock'
require 'chkbuild/cvs'
require 'chkbuild/svn'
require 'chkbuild/git'
require 'chkbuild/xforge'
require "util"
require 'chkbuild/target'
require 'chkbuild/build'

module ChkBuild
  autoload :Ruby, 'chkbuild/ruby'
  autoload :GCC, 'chkbuild/gcc'
end
