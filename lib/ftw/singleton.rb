require "ftw/namespace"

module FTW::Singleton
  def self.included(klass)
    raise ArgumentError.new("In #{klass.name}, you want to use 'extend #{self.name}', not 'include ...'")
  end # def included

  def singleton
    @instance ||= self.new
    return @instance
  end # def self.singleton
end # module FTW::Singleton

