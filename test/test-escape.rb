require 'test/unit'
require 'escape'

class TestEscape < Test::Unit::TestCase
  def test_shell_command
    assert_equal("com arg", Escape.shell_command(%w[com arg]))
  end

  def test_html_text
    assert_equal('a&amp;&lt;&gt;"', Escape.html_text('a&<>"'))
  end

  def test_html_attr
    assert_equal('a&amp;&lt;&gt;&quot;', Escape.html_attr('a&<>"'))
  end

end
