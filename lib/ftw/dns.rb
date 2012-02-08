require "ftw/namespace"
require "socket" # for Socket.gethostbyname

# TODO(sissel): Switch to using Resolv::DNS since it lets you (the programmer)
# choose dns configuration (servers, etc)
#
# I wrap whatever Ruby provides because it is historically very
# inconsistent in implementation behavior across ruby platforms and versions.
# In the future, this will probably implement the DNS protocol, but for now
# chill in the awkward, but already-written, ruby stdlib.
#
# I didn't really want to write a DNS library, but a consistent API and
# behavior is necessary for my continued sanity :)
class FTW::DNS
  V4_IN_V6_PREFIX = "0:" * 12

  def self.singleton
    @resolver ||= self.new
  end # def self.singleton

  # This method is only intended to do A or AAAA lookups
  # I may add PTR lookups later.
  def resolve(hostname)
    official, aliases, family, *addresses = Socket.gethostbyname(hostname)
    # We ignore family, here. Ruby will return v6 *and* v4 addresses in
    # the same gethostbyname() call. It is confusing. 
    #
    # Let's just rely entirely on the length of the address string.
    return addresses.collect do |address|
      if address.length == 16
        unpack_v6(address)
      else
        unpack_v4(address)
      end
    end
  end # def resolve

  def resolve_random(hostname)
    addresses = resolve(hostname)
    return addresses[rand(addresses.size)]
  end # def resolve_random

  private
  def unpack_v4(address)
    return address.unpack("C4").join(".")
  end # def unpack_v4

  private
  def unpack_v6(address)
    if address.length == 16
      # Unpack 16 bit chunks, convert to hex, join with ":"
      address.unpack("n8").collect { |p| p.to_s(16) } \
        .join(":").sub(/(?:0:(?:0:)+)/, "::")
    else 
      # assume ipv4
      # Per the following sites, "::127.0.0.1" is valid and correct
      # http://en.wikipedia.org/wiki/IPv6#IPv4-mapped_IPv6_addresses
      # http://www.tcpipguide.com/free/t_IPv6IPv4AddressEmbedding.htm
      "::" + unpack_v4(address)
    end
  end # def unpack_v6
end # class FTW::DNS
