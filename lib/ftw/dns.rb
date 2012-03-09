require "ftw/namespace"
require "socket" # for Socket.gethostbyname
require "ftw/singleton"
require "ftw/dns/dns"

# I wrap whatever Ruby provides because it is historically very
# inconsistent in implementation behavior across ruby platforms and versions.
# In the future, this will probably implement the DNS protocol, but for now
# chill in the awkward, but already-written, ruby stdlib.
#
# I didn't really want to write a DNS library, but a consistent API and
# behavior is necessary for my continued sanity :)
class FTW::DNS
  extend FTW::Singleton

  # The ipv4-in-ipv6 address space prefix.
  V4_IN_V6_PREFIX = "0:" * 12

  # An array of resolvers. By default this includes a FTW::DNS::DNS instance.
  attr_reader :resolvers

  private

  # A new resolver.
  #
  # The default set of resolvers is only {FTW::DNS::DNS} which does DNS
  # resolution.
  def initialize
    @resolvers = [FTW::DNS::DNS.new]
  end # def initialize

  # Resolve a hostname.
  #
  # Returns an array of all addresses for this host. Empty array resolution
  # failure.
  def resolve(hostname)
    return @resolvers.reduce([]) do |memo, resolver|
      result = resolver.resolve(hostname)
      memo += result unless result.nil?
    end
  end # def resolve

  # Resolve hostname and choose one of the results at random.
  # 
  # Use this method if you are connecting to a hostname that resolves to
  # multiple addresses.
  def resolve_random(hostname)
    addresses = resolve(hostname)
    return addresses[rand(addresses.size)]
  end # def resolve_random

  public(:resolve, :resolve_random)
end # class FTW::DNS
