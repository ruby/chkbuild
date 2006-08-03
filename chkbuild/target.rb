class ChkBuild::Target
  def initialize(target_name, *args, &block)
    @target_name = target_name
    @build_proc = block
    @opts = {}
    @opts = args.pop if Hash === args.last
    init_perm_target(*args)
    @title_hook = []
    init_default_title_hooks
  end
  attr_reader :target_name, :opts, :build_proc

  def init_perm_target(*args)
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
    Util.permutation(*suffixes_ary) {|suffixes|
      suffixes.compact!
      if suffixes.empty?
        @branches << [nil, *suffixes]
      else
        @branches << [suffixes.join('-'), *suffixes]
      end
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
    add_title_hook("end") {|b, log|
      num_warns = b.all_log.scan(/warn/i).length
      b.update_title(:warn) {|val| "#{num_warns}W" } if 0 < num_warns
    }
  end

  def add_title_hook(secname, &block) @title_hook << [secname, block] end
  def each_title_hook(&block) @title_hook.each(&block) end

  def start_perm
    return @result if defined? @result
    succeed = Depend.new
    @branches.each {|branch_suffix, *branch_info|
      dep_results = @dep_targets.map {|dep_target| dep_target.result }
      Util.permutation(*dep_results) {|dependencies|
        name = @target_name.dup
        name << "-#{branch_suffix}" if branch_suffix
        simple_name = name.dup
        dep_dirs = []
        dep_versions = []
        dependencies.each {|dep_target_name, dep_branch_suffix, dep_dir, dep_ver|
          name << "_#{dep_target_name}"
          name << "-#{dep_branch_suffix}" if dep_branch_suffix
          dep_dirs << "#{dep_target_name}=#{dep_dir}"
          dep_versions.concat dep_ver
        }
        title = {}
        title[:version] = simple_name
        title[:dep_versions] = dep_versions
        title[:hostname] = "(#{Socket.gethostname.sub(/\..*/, '')})"
        status, dir, version_list = Build.new(self).build_in_child(name, title, branch_info+dep_dirs)
        if status.to_i == 0
          succeed.add [@target_name, branch_suffix, dir, version_list] if status.to_i == 0
        end
      }
    }
    @result = succeed
    succeed
  end

  def result
    return @result if defined? @result
    raise "#{@target_name}: no result yet"
  end

  class Depend
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