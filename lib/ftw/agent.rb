require "ftw/namespace"
require "ftw/request"
require "ftw/connection"
require "addressable/uri"

# This should act as a proper agent.
#
# * Keep cookies. Offer local-storage of cookies
# * Reuse connections. HTTP 1.1 Connection: keep-alive
# * HTTP Upgrade support
# * Websockets
# * SSL/TLS
class FTW::Agent
  # TODO(sissel): All standard HTTP methods should be defined here.
  # Also allow users to specify non-standard methods.
  
  def initialize
  end

  # Returns a FTW::Request
  # TODO(sissel): SSL/TLS support
  def get(uri, options={})
    return request("GET", uri, options)
  end # def get

  def request(method, uri, options)
    request = FTW::Request.new(uri)
    request.method = method
    request.connection = connection(uri.host, uri.port)
    return request
  end # def request

  # Returns a FTW::Connection connected to this host:port.
  # TODO(sissel): Implement connection reuse
  # TODO(sissel): support SSL/TLS
  private
  def connection(host, port)
    return FTW::Connection.new("#{host}:#{port}")
  end # def connect
end # class FTW::Agent
