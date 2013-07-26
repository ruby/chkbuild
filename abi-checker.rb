# abi-checker.rb - ABI checker for Ruby
#
# Copyright (C) 2013 KOSAKI Motohiro <kosaki.motohiro@gmail.com>
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

require 'tempfile'
require "optparse"

skip_headers = <<END
classext.h
rubyio.h
rubysig.h
missing.h
oniguruma.h
re.h
regex.h
version.h
END

skip_symbols = <<END
ruby_description
END

xml_template = <<END
    <version>
      unspecified
    </version>

    <headers>
      {RELPATH}/include/
    </headers>

    <libs>
      {RELPATH}/lib
    </libs>
END

opts = OptionParser.new
opts.on("--skip-symbols FILE") {|f|
  # If --skip-symbols is specified, they are skipped too.
  skip_symbols += File.open(f).read
}
opts.parse!(ARGV)

if ARGV.size < 2 then
  puts "usage: abi-checker [--skip-symbols FILE] path-to-old-ruby path-to-new-ruby"
end


sh_file = Tempfile.open("skip-headers")
sh_file.write(skip_headers)
sh_file.flush

ss_file = Tempfile.open("skip-symbols")
ss_file.write(skip_symbols)
ss_file.flush

template_file = Tempfile.open(["version-template", ".xml"])
template_file.write(xml_template)
template_file.flush

`abi-compliance-checker -abi -lib libruby -old #{template_file.path} -relpath1 #{ARGV[0]} -new #{template_file.path} -relpath2 #{ARGV[1]} -skip-headers #{sh_file.path} -skip-symbols #{ss_file.path} `

