module ChkBuild
  @default_options = {
    :num_oldbuilds => 3,
    :limit_cpu => 3600 * 4,
    :limit_stack => 1024 * 1024 * 40,
    :limit_data => 1024 * 1024 * 100,
    :limit_as => 1024 * 1024 * 100
  }

  def self.num_oldbuilds
    @default_options[:num_oldbuilds]
  end
  def self.num_oldbuilds=(val)
    @default_options[:num_oldbuilds] = val
  end

  def self.limit(hash)
    hash.each {|k, v|
      s = "limit_#{k}".intern
      raise "unexpected resource name: #{k}" if !@default_options[s]
      @default_options[s] = v
    }
  end

  def self.get_limit
    ret = {}
    @default_options.each {|k, v|
      next if /\Alimit_/ !~ k.to_s
      s = $'.intern
      ret[s] = v
    }
    ret
  end
end
