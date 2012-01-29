require File.join(File.expand_path(__FILE__).sub(/\/net\/ftw\/.*/, "/testing"))
require "net/ftw/crlf"

describe Net::FTW::CRLF do
  test "CRLF is as expected" do
    class Foo
      include Net::FTW::CRLF
    end

    assert_equal("\r\n", Foo::CRLF)
  end
end
