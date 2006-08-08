require 'util'

class ChkBuild::Title
  def initialize(target, start_time, logfile)
    @target = target
    @start_time = start_time
    @logfile = logfile
    @title = {}
    @title[:version] = @logfile.suffixed_name
    @title[:dep_versions] = []
    @title[:hostname] = "(#{Util.simple_hostname})"
    @title_order = [:status, :warn, :mark, :version, :dep_versions, :hostname]
  end

  def versions
    return ["#{@start_time} #{@title[:version]}", *@title[:dep_versions]]
  end

  def depsuffixed_name() @logfile.depsuffixed_name end
  def suffixed_name() @logfile.suffixed_name end
  def target_name() @logfile.target_name end
  def suffixes() @logfile.suffixes end

  def run_title_hooks
    @target.each_title_hook {|secname, block|
      if secname == nil
        block.call self, @logfile.get_all_log
      elsif log = @logfile.get_section(secname)
        block.call self, log
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
      if key == :dep_versions
        title_hash[key].map {|ver| "(#{ver})" }
      else
        title_hash[key]
      end
    }.flatten.join(' ').gsub(/\s+/, ' ').strip
  end

  def [](key)
    @title[key]
  end
end
