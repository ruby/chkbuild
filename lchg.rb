module Lchg
  def Lchg.each_context(enum, pred, context)
    buf = []
    after_match = false
    i = 0
    enum.each {|elt|
      test = pred.call(elt)
      if test
        b = i - buf.length
        buf.each_with_index {|(t, e), j|
          yield b+j, t, e
        }
        buf.clear
        yield i, test, elt
        after_match = true
      else
        if after_match
          if buf.length == context
            b = i - buf.length
            buf.each_with_index {|(t, e), j|
              yield b+j, t, e
            }
            buf.clear
            after_match = false
          end
          buf << [test, elt]
        else
          if buf.length == context
            buf.shift
          end
          buf << [test, elt]
        end
      end
      i += 1
    }
    if after_match
      b = i - buf.length
      buf.each_with_index {|(t, e), j|
        yield b+j, t, e
      }
    end
  end

  def Lchg.line_additions(path1, path2, context)
    h = {}
    File.foreach(path1) {|line|
      h[line] = true
    }
    File.open(path2) {|f2|
      pred = lambda {|line| !h[line] }
      each_context(f2, pred, context) {|i, t, line|
        yield i, t, line
      }
    }
  end

  def Lchg.fcmp(path1, path2, out, header1, header2)
    first = true
    found = false
    context = 3
    last = nil
    Lchg.line_additions(path1, path2, context) {|i, t, line|
      found = true
      i += 1
      if !last
        first = false
        out.puts '==================================================================='
        out.puts header2
        last = -1
      end
      out.puts "@@ #{i} @@" if last + 1 != i
      mark = t ? "+" : " "
      out.puts "#{mark}#{line}"
      last = i
    }
    last = nil
    Lchg.line_additions(path2, path1, context) {|i, t, line|
      found = true
      i += 1
      if !last
        out.puts if !first
        out.puts '==================================================================='
        out.puts header1
        last = -1
      end
      out.puts "@@ #{i} @@" if last + 1 != i
      mark = t ? "-" : " "
      out.puts "#{mark}#{line}"
      last = i
    }
    found
  end

  def Lchg.diff(path1, path2, out, header1="--- #{path1}\n", header2="+++ #{path2}\n")
    Lchg.fcmp(path1, path2, out, header1, header2)
  end
end
