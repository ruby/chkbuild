class ChkBuild::Target
  def initialize(target_name, *args, &block)
    @target_name = target_name
    @build_proc = block
    @opts = {}
    @opts = args.pop if Hash === args.last
    init_target(*args)
    @title_hook = []
    init_default_title_hooks
  end
  attr_reader :target_name, :opts, :build_proc

  def init_target(*args)
    @dep_targets = []
    suffixes_ary = []
    args.each {|arg|
      if ChkBuild::Target === arg
        @dep_targets << arg
      else
        suffixes_ary << arg
      end
    }
    @branches = []
    Util.rproduct(*suffixes_ary) {|suffixes|
      suffixes.compact!
      @branches << suffixes
    }
  end

  def init_default_title_hooks
    add_title_hook('success') {|b, log|
      b.update_title(:status) {|val| 'success' if !val }
    }
    add_title_hook('failure') {|b, log|
      b.update_title(:status) {|val|
        if !val
          line = /\n/ =~ log ? $` : log
          line = line.strip
          line if !line.empty?
        end
      }
    }
    add_title_hook(nil) {|b, log|
      num_warns = log.scan(/warn/i).length
      b.update_title(:warn) {|val| "#{num_warns}W" } if 0 < num_warns
    }
  end

  def add_title_hook(secname, &block) @title_hook << [secname, block] end
  def each_title_hook(&block) @title_hook.each(&block) end

  def each_suffix_list
    @branches.each {|suffix_list|
      yield suffix_list
    }
  end

  def make_result
    return @result if defined? @result
    succeed = Result.new
    each_suffix_list {|suffix_list|
      dep_results = @dep_targets.map {|dep_target| dep_target.result }
      Util.rproduct(*dep_results) {|dependencies|
        build = Build.new(self, suffix_list)
        dependencies.each {|depbuild| build.add_depbuild depbuild }
        succeed.add(build) if build.build
      }
    }
    @result = succeed
    succeed
  end

  def result
    return @result if defined? @result
    raise "#{@target_name}: no result yet"
  end

  class Result
    def initialize
      @list = []
    end

    def add(elt)
      @list << elt
    end

    def each
      @list.each {|elt| yield elt }
    end
  end
end
