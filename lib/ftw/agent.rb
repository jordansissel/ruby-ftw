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
#
# TODO(sissel): TBD: implement cookies... delicious chocolate chip cookies.
class FTW::Agent
  def initialize
    @pool = FTW::Pool.new
    @logger = Cabin::Channel.get($0)
    @logger.subscribe(Logger.new(STDOUT))
    @logger.level = :warn

    @redirect_max = 20
  end # def initialize

  # Define all the standard HTTP methods (Per RFC2616)
  # As an example, for "get" method, this will define these methods:
  # 
  # * FTW::Agent#get(uri, options={})
  # * FTW::Agent#get!(uri, options={})
  #
  # The first one returns a FTW::Request you must pass to Agent#execute(...)
  # The second does the execute for you and returns a FTW::Response.
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
  # This will send the http request. If the websocket handshake
  # is successful, a FTW::WebSocket instance will be returned.
  # Otherwise, a FTW::Response will be returned.
  public
  def websocket!(uri, options={})
    req = request("GET", uri, options)
    ws = FTW::WebSocket.new(req)
    response = execute(req)
    if ws.handshake_ok?(response)
      # response.body is a FTW::Connection
      ws.connection = response.body

      # There seems to be a bug in http_parser.rb where websocket
      # responses lead with a newline for some reason. Work around it.
      data = response.body.read
      if data[0] == "\n"
        response.body.pushback(data[1..-1])
      else
        response.body.pushback(data)
      end
      return ws
    else
      return response
    end
  end # def websocket!

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
    connection.secure if request.protocol == "https"
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

      # TODO(sissel): If this response has any cookies, store them in the
      # agent's cookie store

      @logger.debug("Redirecting", :location => response.headers["Location"])
      redirects += 1
      request.use_uri(response.headers["Location"])
      connection = connect(request.headers["Host"], request.port)
      connection.secure if request.protocol == "https"
      response = request.execute(connection)
    end

    # RFC 2616 section 9.4, HEAD requests MUST NOT have a message body.
    if request.method != "HEAD"
      response.body = connection
    else
      connection.release
    end
   
    # TODO(sissel): If this response has any cookies, store them in the
    # agent's cookie store
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
