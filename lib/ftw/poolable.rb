
require "ftw/namespace"

module FTW::Poolable
  def mark
    @__in_use = true
  end # def mark

  def release
    @__in_use = false
  end # def release

  def available?
    return !@__in_use
  end # def avialable?
end # module FTW::Poolable
