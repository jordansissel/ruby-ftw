require "ftw/namespace"

class FTW::Pool
  def initialize
    # Pool is a hash of arrays.
    @pool = Hash.new { |h,k| h[k] = Array.new }
  end # def initialize

  def add(identifier, object)
    @pool[identifier] << object
    return object
  end # def add

  def fetch(identifier, &default_block)
    object = @pool[identifier].find { |o| o.available? }
    return object if !object.nil?
    # Otherwise put the return value of default_block in the
    # pool and return it.
    return add(identifier, default_block.call)
  end # def fetch
end # class FTW::Pool
