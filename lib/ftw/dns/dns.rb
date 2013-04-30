require "ftw/namespace"

# A FTW::DNS resolver that uses Socket.gethostbyname() to resolve addresses.
class FTW::DNS::DNS
  # TODO(sissel): Switch to using Resolv::DNS since it lets you (the programmer)
  # choose dns configuration (servers, etc)
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

  # Unserialize a 4-byte ipv4 address into a human-readable a.b.c.d string
  def unpack_v4(address)
    return address.unpack("C4").join(".")
  end # def unpack_v4

  # Unserialize a 16-byte ipv6 address into a human-readable a:b:c:...:d string
  def unpack_v6(address)
    if address.length == 16
      # Unpack 16 bit chunks, convert to hex, join with ":"
      address.unpack("n8").collect { |p| p.to_s(16) } \
        .join(":").sub(/(?:0:(?:0:)+)/, ":")
    else 
      # assume ipv4
      # Per the following sites, "::127.0.0.1" is valid and correct
      # http://en.wikipedia.org/wiki/IPv6#IPv4-mapped_IPv6_addresses
      # http://www.tcpipguide.com/free/t_IPv6IPv4AddressEmbedding.htm
      "::" + unpack_v4(address)
    end
  end # def unpack_v6

  public(:resolve)
end # class FTW::DNS::DNS
