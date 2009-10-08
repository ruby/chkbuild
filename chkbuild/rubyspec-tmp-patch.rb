# This definition redefine mspec/lib/mspec/helpers/tmp.rb.

# http://rubyspec.org/issues/show/154

class Object
  def tmp(name)
    t = ENV.fetch("TMPDIR", "/tmp")
    File.join t, name
  end
end
