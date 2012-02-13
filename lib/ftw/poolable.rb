require "ftw/namespace"

# A poolable mixin. This is for use with the FTW::Pool class.
module FTW::Poolable
  # Mark that this resource is in use
  def mark
    @__in_use = true
  end # def mark

  # Release this resource
  def release
    @__in_use = false
  end # def release

  # Is this resource available for use?
  def available?
    return !@__in_use
  end # def avialable?
end # module FTW::Poolable
