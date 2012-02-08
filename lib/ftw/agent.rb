require "ftw/namespace"
require "ftw/request"
require "ftw/connection"
require "addressable/uri"
require "cabin"
require "logger"

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
    @logger = Cabin::Channel.new
    @logger.subscribe(Logger.new(STDOUT))

    @redirect_max = 20
  end # def initialize

  # Returns a FTW::Request
  # TODO(sissel): SSL/TLS support
  public
  def get(uri, options={})
    return request("GET", uri, options)
  end # def get

  public
  def head(uri, options={})
    return request("HEAD", uri, options)
  end # def get

  public
  def request(method, uri, options)
    @logger.info("Creating new request", :method => method, :uri => uri, :options => options)
    request = FTW::Request.new(uri)
    request.method = method
    request.headers.add("Connection", "keep-alive")
    return request
  end # def request

  public
  def execute(request)
    connection = connection(request.headers["Host"], request.port)
    response = request.execute(connection)

    redirects = 0
    while response.redirect? and response.headers.include?("Location")
      @logger.info("Redirecting", :location => response.headers["Location"])
      redirects += 1
      connection = connection(request.headers["Host"], request.port)
      request.use_uri(response.headers["Location"])
      response = request.execute(connection)
    end

    response.body = connection
    return response
  end # def execute

  # Returns a FTW::Connection connected to this host:port.
  # TODO(sissel): Implement connection reuse
  # TODO(sissel): support SSL/TLS
  private
  def connection(host, port)
    connection = FTW::Connection.new("#{host}:#{port}")
    @logger.info("Connecting", :connection => connection)
    connection.connect
    return connection
  end # def connect
end # class FTW::Agent
