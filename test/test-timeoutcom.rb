require 'timeoutcom'
require 'test/unit'

class TestTimeoutCommand < Test::Unit::TestCase
  def test_time
    assert_raise(CommandTimeout) {
      open("/dev/null", 'w') {|null|
        TimeoutCommand.timeout_command(Time.now+1, null) {
          begin
            sleep 2
          rescue Interrupt
          end
        }
      }
    }
  end

  def test_past_time
    assert_raise(CommandTimeout) {
      TimeoutCommand.timeout_command(Time.now-1, nil) {}
    }
  end
end
