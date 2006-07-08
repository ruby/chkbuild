require 'test/unit'
require 'tempfile'
require 'logfile'

class TestLogFile < Test::Unit::TestCase
  def with_logfile
    t = Tempfile.new("test-logfile")
    begin
      l = LogFile.new(t.path)
      yield l
    ensure
      t.close(true)
    end
  end

  def test_start_section
    with_logfile {|l|
      l.start_section("a")
      assert_match(/^== a #/, l.get_all_log)
    }
  end

  def test_get_section
    with_logfile {|l|
      l.with_default_output {
        l.start_section("a")
        puts "aaa"
        l.start_section("b")
        puts "bbb"
      }
      assert_equal("aaa\n", l.get_section("a"))
      assert_equal("bbb\n", l.get_section("b"))
    }
  end

  def test_unique_section_name
    with_logfile {|l|
      secname1 = l.start_section("a")
      secname2 = l.start_section("a")
      secname3 = l.start_section("a")
      secname5 = l.start_section("a (5)")
      secname4 = l.start_section("a")
      secname6 = l.start_section("a")
      assert_equal("a", secname1)
      assert_equal("a (2)", secname2)
      assert_equal("a (3)", secname3)
      assert_equal("a (4)", secname4)
      assert_equal("a (5)", secname5)
      assert_equal("a (6)", secname6)
      assert_match(/^== #{Regexp.quote secname1} #/, l.get_all_log)
      assert_match(/^== #{Regexp.quote secname2} #/, l.get_all_log)
      assert_match(/^== #{Regexp.quote secname3} #/, l.get_all_log)
    }
  end

end
