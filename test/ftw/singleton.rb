require File.join(File.expand_path(__FILE__).sub(/\/ftw\/.*/, "/testing"))
require "ftw/singleton"

describe FTW::Singleton do
  test "extending with FTW::Singleton gives a singleton method" do
    class Foo
      extend FTW::Singleton
    end
    assert_respond_to(Foo, :singleton)
  end

  test "FTW::Singleton gives a singleton instance" do
    class Foo
      extend FTW::Singleton
    end
    assert_instance_of(Foo, Foo.singleton)
    assert_equal(Foo.singleton.object_id, Foo.singleton.object_id)
  end
end
