require "ftw/namespace"
require "ftw/request"
require "ftw/connection"
require "ftw/pool"
require "ftw/websocket"
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
    @logger.level = :debug
    @pool = FTW::Pool.new

    @redirect_max = 20
  end # def initialize

  %w(options get head post put delete trace connect).each do |name|
    m = name.upcase

    # define 'get' etc method.
    define_method(name.to_sym) do |uri, options={}|
      return request(m, uri, options)
    end

    # define 'get!' etc method.
    define_method("#{name}!".to_sym) do |uri, options={}|
      return execute(request(m, uri, options))
    end
  end

  # Send the request as an HTTP upgrade.
  # 
  # Returns the response and the FTW::Connection for this connection.
  # If the upgrade was denied, the connection returned will be nil.
  def upgrade!(uri, protocol, options={})
    req = request("GET", uri, options)
    req.headers["Connection"] = "Upgrade"
    req.headers["Upgrade"] = protocol
    response = execute(req)
    if response.status == 101
      return response, response.body
    else
      return response, nil
    end
  end # def upgrade

  # Make a new websocket connection
  public
  def websocket!(uri, options={})
    req = request("GET", uri, options)
    ws = FTW::WebSocket.new(req)
    response = execute(req)
    if ws.handshake_ok?(response)
      # response.body is a FTW::Connection
      ws.connection = response.body
      p response.body.read
      return ws
    else
      return response
    end
  end # def websocket

  public
  def request(method, uri, options)
    @logger.info("Creating new request", :method => method, :uri => uri, :options => options)
    request = FTW::Request.new(uri)
    request.method = method
    request.headers.add("Connection", "keep-alive")

    if options.include?(:headers)
      options[:headers].each do |key, value|
        request.headers.add(key, value)
      end
    end

    return request
  end # def request

  public
  def execute(request)
    # TODO(sissel): Make redirection-following optional, but default.

    connection = connect(request.headers["Host"], request.port)
    response = request.execute(connection)

    redirects = 0
    while response.redirect? and response.headers.include?("Location")
      redirects += 1
      if redirects > @redirect_max
        # TODO(sissel): Abort somehow...
      end
      # RFC2616 section 10.3.3 indicates HEAD redirects must not include a
      # body. Otherwise, the redirect response can have a body, so let's
      # throw it away.
      if request.method == "HEAD" 
        # Head requests have no body
        connection.release
      elsif response.content?
        # Throw away the body
        response.body = connection
        # read_body will release the connection
        response.read_body { |chunk| }
      end

      @logger.debug("Redirecting", :location => response.headers["Location"])
      redirects += 1
      request.use_uri(response.headers["Location"])
      connection = connect(request.headers["Host"], request.port)
      response = request.execute(connection)
    end

    # RFC 2616 section 9.4, HEAD requests MUST NOT have a message body.
    if request.method != "HEAD"
      response.body = connection
    else
      connection.release
    end
    return response
  end # def execute

  # Returns a FTW::Connection connected to this host:port.
  # TODO(sissel): Implement connection reuse
  # TODO(sissel): support SSL/TLS
  private
  def connect(host, port)
    address = "#{host}:#{port}"
    @logger.debug("Fetching from pool", :address => address)
    connection = @pool.fetch(address) do
      @logger.info("New connection to #{address}")
      connection = FTW::Connection.new(address)
      connection.connect
      connection
    end
    @logger.debug("Pool fetched a connection", :connection => connection)
    connection.mark
    return connection
  end # def connect
end # class FTW::Agent
