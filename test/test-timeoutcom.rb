require 'timeoutcom'
require 'test/unit'

class TestTimeoutCommand < Test::Unit::TestCase
  def test_time
    assert_raise(TimeoutError) {
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
end
