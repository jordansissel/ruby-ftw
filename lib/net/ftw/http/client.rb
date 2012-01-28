require "net/ftw/namespace"
require "net/ftw/http/request"
require "net/ftw/http/response"
require "socket" # ruby stdlib

# TODO(sissel): Split this out into a general 'client' class (outside http)
# TODO(sissel): EventMachine support

# A client should be like a web browser. It should support lots of active
# connections.
class Net::FTW::HTTP::Client
  # Create a new HTTP client. You probably only need one of these.
  def initialize
    @connections = []
  end # def initialize
  
  # TODO(sissel): This method may not stay. I dunno yet.
  public
  def get(uri, &block)
    start("GET", uri, &block)
  end # def get

  public
  def start(method, uri, &block)
    if !block_given?
      raise ArgumentError.new("No block given to #{self.class.name}#start" \
        "(#{method.inspect}, #{uri.inspect}")
    end
    uri = Addressable::URI.parse(uri.to_s) if uri.is_a?(URI)

    req = Net::FTW::HTTP::Request.new(uri)
    resp = Net::FTW::HTTP::Response.new

    req.method = method
    req.version = 1.1

    # TODO(sissel): Implement retries on certain failures like DNS, connect
    # timeouts, or connection resets?
    # TODO(sissel): use HTTPS if the uri.scheme == "https"
    # TODO(sissel): Resolve the hostname
    # TODO(sissel): Start a new connection, or reuse an existing one.
    block.call(req, resp)
  end # def start
end # class Net::FTW::HTTP::Client
