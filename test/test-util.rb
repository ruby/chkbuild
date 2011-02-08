require 'test/unit'
require 'util'

class TestUtil < Test::Unit::TestCase
  def test_opts2aryparam_configure_args
    opts = {
      :configure_args => [],
      :configure_args_valgrind => ["--with-valgrind"],
    }
    assert_equal(["--with-valgrind"], Util.opts2aryparam(opts, :configure_args))
  end

  def test_opts2aryparam_num
    opts = { :foo_1 => "a", :foo_9 => "b", :foo_10 => "c" }
    assert_equal(["a", "b", "c"], Util.opts2aryparam(opts, :foo))
  end

  def test_opts2aryparam_key
    opts = { :foo => [:a, :b], :foo_a => "A", :foo_b => "B", }
    assert_equal(["A", "B"], Util.opts2aryparam(opts, :foo))
    opts = { :foo => [:b, :a], :foo_a => "A", :foo_b => "B", }
    assert_equal(["B", "A"], Util.opts2aryparam(opts, :foo))
    opts = { :foo => [:b, :a], :foo_a => ["A"], :foo_b => "B", }
    assert_equal(["B", "A"], Util.opts2aryparam(opts, :foo))
    opts = { :foo => [:b, :a], :foo_a => "A", :foo_b => ["B", "BB"], }
    assert_equal(["B", "BB", "A"], Util.opts2aryparam(opts, :foo))
    opts = { :foo => [:a], :foo_a => "A", :foo_b => "B", :foo_9 => "Q", :foo_10 => "J" }
    assert_equal(["A", "Q", "J", "B"], Util.opts2aryparam(opts, :foo))
    opts = { :foo => [:a, :b_?, :c], :foo_a => "A", :foo_b_9 => "BQ", :foo_b_10 => "BJ", :foo_c => "C", :foo_A => "aa" }
    assert_equal(%w[A BQ BJ C aa], Util.opts2aryparam(opts, :foo))
  end

end
