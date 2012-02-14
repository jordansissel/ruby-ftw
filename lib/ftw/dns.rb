require "ftw/namespace"
require "socket" # for Socket.gethostbyname

# I wrap whatever Ruby provides because it is historically very
# inconsistent in implementation behavior across ruby platforms and versions.
# In the future, this will probably implement the DNS protocol, but for now
# chill in the awkward, but already-written, ruby stdlib.
#
# I didn't really want to write a DNS library, but a consistent API and
# behavior is necessary for my continued sanity :)
class FTW::DNS
  # TODO(sissel): Switch to using Resolv::DNS since it lets you (the programmer)
  # choose dns configuration (servers, etc)

  V4_IN_V6_PREFIX = "0:" * 12

  # Get a singleton instance of FTW::DNS
  def self.singleton
    @resolver ||= self.new
  end # def self.singleton

  private

  # Resolve a hostname.
  #
  # It will return an array of all known addresses for the host.
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

  # Resolve hostname and choose one of the results at random.
  # 
  # Use this method if you are connecting to a hostname that resolves to
  # multiple addresses.
  def resolve_random(hostname)
    addresses = resolve(hostname)
    return addresses[rand(addresses.size)]
  end # def resolve_random

  def unpack_v4(address)
    return address.unpack("C4").join(".")
  end # def unpack_v4

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

  public(:resolve, :resolve_random)
end # class FTW::DNS
