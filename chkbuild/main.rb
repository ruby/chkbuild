module ChkBuild
  TOP_DIRECTORY = Dir.getwd
  def ChkBuild.build_dir() "#{TOP_DIRECTORY}/tmp/build" end
  def ChkBuild.public_dir() "#{TOP_DIRECTORY}/tmp/public_html" end
end
