# lchg.rb - line changes detection library
#
# Copyright (C) 2010 Tanaka Akira  <akr@fsij.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#  3. The name of the author may not be used to endorse or promote
#     products derived from this software without specific prior
#     written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'tempfile'
require 'escape'

module Lchg
  def Lchg.each_context(enum, scanner, pred, context=3)
    buf = []
    after_match = false
    i = 0
    enum.each {|elt|
      scanner.call(elt) if scanner
      not_exist = pred.call(elt)
      if not_exist
        b = i - buf.length
        buf.each_with_index {|(t, e), j|
          yield b+j, t, e
        }
        buf.clear
        yield i, not_exist, elt
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
          buf << [not_exist, elt]
        else
          if buf.length == context
            buf.shift
          end
          buf << [not_exist, elt]
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

  def Lchg.encode_pair(num, str)
    hex = str.unpack("H*")[0]
    return "#{num} #{hex}"
  end

  def Lchg.decode_pair(line)
    return nil if line == nil
    num, hex = line.chomp.split(/ /)
    return [num.to_i, [hex].pack("H*")]
  end

  def Lchg.encode_lines(path)
    tf = Tempfile.open("lchg-a")
    File.open(path) {|f|
      f.each_with_index {|line, i|
        line.chomp!
        tf.puts encode_pair(i, line)
      }
    }
    tf.flush
    tf
  end

  def Lchg.sort_by_content(path)
    tf = Tempfile.open("lchg-b")
    command = ["sort", "-k", "2", path]
    IO.popen("#{Escape.shell_command command}") {|f|
      while line = f.gets
        tf.puts line
      end
    }
    tf.flush
    tf
  end

  def Lchg.sync_each(tf1, tf2)
    numline1 = decode_pair(tf1.gets)
    numline2 = decode_pair(tf2.gets)
    prev = nil
    buf1 = []
    buf2 = []
    while numline1 || numline2
      if numline2 == nil || (numline1 != nil && numline1[1] <= numline2[1])
        if !prev || prev == numline1[1]
          prev = numline1[1]
          buf1 << numline1
        else
          yield buf1, buf2
          prev = numline1[1]
          buf1 = [numline1]
          buf2 = []
        end
        numline1 = decode_pair(tf1.gets)
      else
        if !prev || prev == numline2[1]
          prev = numline2[1]
          buf2 << numline2
        else
          yield buf1, buf2
          prev = numline2[1]
          buf1 = []
          buf2 = [numline2]
        end
        numline2 = decode_pair(tf2.gets)
      end
    end
    if !buf1.empty? || !buf2.empty?
      yield buf1, buf2
    end
  end

  def Lchg.add_mark(src1, src2)
    src1.rewind
    src2.rewind
    dst1 = Tempfile.open("lchg-c")
    dst2 = Tempfile.open("lchg-c")
    numdel = 0
    numadd = 0
    sync_each(src1, src2) {|buf1, buf2|
      if buf1.empty?
        buf2.each {|num, line|
          numadd += 1
          dst2.puts encode_pair(num, "+"+line)
        }
      elsif buf2.empty?
        buf1.each {|num, line|
          numdel += 1
          dst1.puts encode_pair(num, "-"+line)
        }
      else
        buf1.each {|num, line|
          dst1.puts encode_pair(num, " "+line)
        }
        buf2.each {|num, line|
          dst2.puts encode_pair(num, " "+line)
        }
      end
    }
    dst1.flush
    dst2.flush
    [numdel, numadd, dst1, dst2]
  end

  def Lchg.sort_by_linenum(path)
    tf = Tempfile.open("lchg-d")
    command = ["sort", "-n", path]
    IO.popen("#{Escape.shell_command command}") {|f|
      while line = f.gets
        tf.puts line
      end
    }
    tf.flush
    tf
  end

  def Lchg.output_changes(header, tf, out, scanner=nil)
    out.puts '==================================================================='
    out.puts header
    tf.rewind
    last = -1
    if scanner
      scanner2 = lambda {|line|
        linenumz, line = decode_pair(line)
        /\A./ =~ line
        scanner.call(linenumz+1, $&, $')
      }
    end
    each_context(tf, scanner2, lambda {|line| / 20/ !~ line }) {|i, t, line|
      num, str = decode_pair(line)
      out.puts "@@ #{i} @@" if last + 1 != num
      out.puts str
      last = num
    }
  end

  def Lchg.diff(path1, path2, out, header1="--- #{path1}\n", header2="+++ #{path2}\n", scanner=nil)
    tf1a = encode_lines(path1)
    #puts tf1a.path; print File.read(tf1a.path)
    tf1b = sort_by_content(tf1a.path)
    #puts tf1b.path; print File.read(tf1b.path)
    tf1a.close(true)
    tf2a = encode_lines(path2)
    #puts tf2a.path; print File.read(tf2a.path)
    tf2b = sort_by_content(tf2a.path)
    #puts tf2b.path; print File.read(tf2b.path)
    tf2a.close(true)
    numdel, numadd, tf1c, tf2c = add_mark(tf1b, tf2b)
    #puts tf1c.path; print File.read(tf1c.path)
    #puts tf2c.path; print File.read(tf2c.path)
    tf1b.close(true)
    tf2b.close(true)
    tf1d = sort_by_linenum(tf1c.path)
    tf1c.close(true)
    tf2d = sort_by_linenum(tf2c.path)
    tf2c.close(true)
    if numadd != 0
      new_scanner = lambda {|linenum, mark, line| scanner.call(:new, linenum, mark, line) } if scanner
      Lchg.output_changes(header2, tf2d, out, new_scanner)
    end
    out.puts if numdel != 0 && numadd != 0
    if numdel != 0
      old_scanner = lambda {|linenum, mark, line| scanner.call(:old, linenum, mark, line) } if scanner
      Lchg.output_changes(header1, tf1d, out, old_scanner)
    end
    numadd != 0 || numdel != 0
  end

end
