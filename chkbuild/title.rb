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
