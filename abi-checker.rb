require 'tempfile'

if ARGV.size < 2 then
  puts "usage: abi-checker path-to-old-ruby path-to-new-ruby"
end

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

sh_file = Tempfile.open("skip-headers")
sh_file.write(skip_headers)
sh_file.flush

ss_file = Tempfile.open("skip-symbols")
ss_file.write(skip_symbols)
ss_file.flush

template_file = Tempfile.open(["version-template", ".xml"])
template_file.write(xml_template)
template_file.flush

`abi-compliance-checker -lib libruby -old #{template_file.path} -relpath1 #{ARGV[0]} -new #{template_file.path} -relpath2 #{ARGV[1]} -skip-headers #{sh_file.path} -skip-symbols #{ss_file.path} `

