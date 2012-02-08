require File.join(File.expand_path(__FILE__).sub(/\/ftw\/.*/, "/testing"))
require "ftw/crlf"

describe FTW::CRLF do
  test "CRLF is as expected" do
    class Foo
      include FTW::CRLF
    end

    assert_equal("\r\n", Foo::CRLF)
  end
end
