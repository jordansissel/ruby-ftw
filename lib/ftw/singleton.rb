require "ftw/namespace"

# A mixin that provides singleton-ness
#
# Usage:
#
#     class Foo
#       extend FTW::Singleton
#
#       ...
#     end
#
# foo = Foo.singleton
module FTW::Singleton
  # This is invoked when you include this module. It raises an exception because you should be
  # using 'extend' not 'include' for this module..
  def self.included(klass)
    raise ArgumentError.new("In #{klass.name}, you want to use 'extend #{self.name}', not 'include ...'")
  end # def included

  # Create a singleton instance of whatever class this module is extended into.
  #
  # Example:
  #
  #     class Foo
  #       extend FTW::Singleton
  #       def bar
  #         "Hello!"
  #       end
  #     end
  #
  #     p Foo.singleton.bar   # == "Hello!"
  def singleton
    @instance ||= self.new
    return @instance
  end # def self.singleton
end # module FTW::Singleton

