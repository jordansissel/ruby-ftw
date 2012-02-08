require File.join(File.expand_path(__FILE__).sub(/\/ftw\/.*/, "/testing"))
require "ftw/http/headers"

describe FTW::HTTP::Headers do
  before do
    @headers = FTW::HTTP::Headers.new
  end

  test "add adds" do
    @headers.add("foo", "bar")
    @headers.add("baz", "fizz")
    assert_equal("fizz", @headers.get("baz"))
    assert_equal("bar", @headers.get("foo"))
  end

  test "add dup field name makes an array" do
    @headers.add("foo", "bar")
    @headers.add("foo", "fizz")
    assert_equal(["bar", "fizz"], @headers.get("foo"))
  end

  test "set replaces" do
    @headers.add("foo", "bar")
    @headers.set("foo", "hello")
    assert_equal("hello", @headers.get("foo"))
  end

  test "remove field" do
    @headers.add("foo", "one")
    @headers.add("bar", "two")
    assert_equal("one", @headers.get("foo"))
    assert_equal("two", @headers.get("bar"))

    @headers.remove("bar")
    assert_equal("one", @headers.get("foo"))
     # bar was removed, must not be present
    assert(!@headers.include?("bar"))
  end

  test "remove field value" do
    @headers.add("foo", "one")
    @headers.add("foo", "two")
    assert_equal(["one", "two"], @headers.get("foo"))

    @headers.remove("foo", "three") # nothing to remove
    assert_equal(["one", "two"], @headers.get("foo"))
    @headers.remove("foo", "two")
    assert_equal("one", @headers.get("foo"))
  end
end # describe FTW::HTTP::Headers
