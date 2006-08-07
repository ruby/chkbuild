class ChkBuild::Target
  def initialize(target_name, *args, &block)
    @target_name = target_name
    @build_proc = block
    @opts = {}
    @opts = args.pop if Hash === args.last
    init_target(*args)
    @title_hook = []
    init_default_title_hooks
    @diff_preprocess_hook = []
    init_default_diff_preprocess_hooks
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
    add_title_hook('success') {|title, log|
      title.update_title(:status) {|val| 'success' if !val }
    }
    add_title_hook('failure') {|title, log|
      title.update_title(:status) {|val|
        if !val
          line = /\n/ =~ log ? $` : log
          line = line.strip
          line if !line.empty?
        end
      }
    }
    add_title_hook(nil) {|title, log|
      num_warns = log.scan(/warn/i).length
      title.update_title(:warn) {|val| "#{num_warns}W" } if 0 < num_warns
    }
    add_title_hook('dependencies') {|title, log|
      dep_versions = []
      log.each_line {|depver|
        dep_versions << depver.chomp
      }
      title.update_title(:dep_versions, dep_versions)
    }
  end

  def add_title_hook(secname, &block) @title_hook << [secname, block] end
  def each_title_hook(&block) @title_hook.each(&block) end

  def init_default_diff_preprocess_hooks
    add_diff_preprocess_hook {|line|
      line.sub(/ # \d{4,}-\d\d-\d\dT\d\d:\d\d:\d\d[-+]\d\d:\d\d$/, '# <time>')
    }
  end

  def add_diff_preprocess_hook(&block) @diff_preprocess_hook << block end
  def each_diff_preprocess_hook(&block) @diff_preprocess_hook.each(&block) end

  def each_suffixes
    @branches.each {|suffixes|
      yield suffixes
    }
  end

  def make_build_objs
    return @builds if defined? @builds
    builds = []
    each_suffixes {|suffixes|
      dep_builds = @dep_targets.map {|dep_target| dep_target.make_build_objs }
      Util.rproduct(*dep_builds) {|dependencies|
        builds << ChkBuild::Build.new(self, suffixes, dependencies)
      }
    }
    @builds = builds
  end
  def each_build_obj(&block)
    make_build_objs.each(&block)
  end

  def make_result
    return @result if defined? @result
    succeed = Result.new
    each_build_obj {|build|
      if build.depbuilds.all? {|depbuild| depbuild.success? }
        succeed.add(build) if build.build
      end
    }
    @result = succeed
    succeed
  end

  def result
    return @result if defined? @result
    raise "#{@target_name}: no result yet"
  end

  class Result
    include Enumerable

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
