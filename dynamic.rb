module Dynamic
  module_function

  DYNAMIC_BINDING_KEY = :dynamic_binding

  def fetch(var)
    b = Thread.current[DYNAMIC_BINDING_KEY]
    while b
      h, b = b
      return h[var] if h.include? var
    end
    yield
  end

  def ref(var)
    fetch(var) { nil }
  end

  def assign(var, val)
    b = Thread.current[DYNAMIC_BINDING_KEY]
    while b
      h, b = b
      if h.include? var
        h[var] = val
        return val
      end
    end
    raise ArgumentError, "no dynamic variable : #{var}"
  end

  def bind(hash)
    old = Thread.current[DYNAMIC_BINDING_KEY]
    if block_given?
      begin
        Thread.current[DYNAMIC_BINDING_KEY] = [hash.dup, old]
        yield
      ensure
        Thread.current[DYNAMIC_BINDING_KEY] = old
      end
    else
      h, b = old
      h.update hash
    end
  end
end
