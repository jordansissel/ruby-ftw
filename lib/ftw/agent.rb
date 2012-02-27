require "ftw/namespace"
require "ftw/request"
require "ftw/connection"
require "ftw/pool"
require "ftw/websocket"
require "addressable/uri"
require "cabin"
require "logger"

# This should act as a proper web agent.
#
# * Reuse connections.
# * SSL/TLS.
# * HTTP Upgrade support.
# * HTTP 1.1 (RFC2616).
# * WebSockets (RFC6455).
# * Support Cookies.
#
# All standard HTTP methods defined by RFC2616 are available as methods on 
# this agent: get, head, put, etc.
#
# Example:
#
#     agent = FTW::Agent.new
#     request = agent.get("http://www.google.com/")
#     response = agent.execute(request)
#     puts response.body.read
#
# For any standard http method (like 'get') you can invoke it with '!' on the end
# and it will execute and return a FTW::Response object:
#
#     agent = FTW::Agent.new
#     response = agent.get!("http://www.google.com/")
#     puts response.body.head
#
# TODO(sissel): TBD: implement cookies... delicious chocolate chip cookies.
class FTW::Agent
  # List of standard HTTP methods described in RFC2616
  STANDARD_METHODS = %w(options get head post put delete trace connect)

  # Everything is private by default.
  # At the bottom of this class, public methods will be declared.
  private

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
  # 
  # For a full list of these available methods, see STANDARD_METHODS.
  STANDARD_METHODS.each do |name|
    m = name.upcase

    # define 'get' etc method.
    define_method(name.to_sym) do |uri, options={}|
      return request(m, uri, options)
    end

    # define 'get!' etc method.
    define_method("#{name}!".to_sym) do |uri, options={}|
      return execute(request(m, uri, options))
    end
  end # STANDARD_METHODS.each

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
  end # def upgrade!

  # Make a new websocket connection.
  #
  # This will send the http request. If the websocket handshake
  # is successful, a FTW::WebSocket instance will be returned.
  # Otherwise, a FTW::Response will be returned.
  #
  # See {#request} for what the 'uri' and 'options' parameters should be.
  def websocket!(uri, options={})
    # TODO(sissel): Use FTW::Agent#upgrade! ?
    req = request("GET", uri, options)
    ws = FTW::WebSocket.new(req)
    response = execute(req)
    if ws.handshake_ok?(response)
      # response.body is a FTW::Connection
      ws.connection = response.body

      # TODO(sissel): Investigate this bug
      # There seems to be a bug in http_parser.rb (or maybe in this library)
      # where websocket responses lead with a newline for some reason. 
      # It's like the header terminator CRLF still has the LF character left
      # in the buffer. Work around it.
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

  # Make a request. Returns a FTW::Request object.
  #
  # Arguments:
  #
  # * method - the http method
  # * uri - the URI to make the request to
  # * options - a hash of options
  #
  # uri can be a valid url or an Addressable::URI object.
  # The uri will be used to choose the host/port to connect to. It also sets
  # the protocol (https, etc). Further, it will set the 'Host' header.
  #
  # The 'options' hash supports the following keys:
  # 
  # * :headers => { string => string, ... }. This allows you to set header values.
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

  # Execute a FTW::Request in this Agent.
  #
  # If an existing, idle connection is already open to the target server
  # of this Request, it will be reused. Otherwise, a new connection
  # is opened.
  #
  # Redirects are always followed.
  #
  # @param [FTW::Request]
  # @return [FTW::Response] the response for this request.
  def execute(request)
    # TODO(sissel): Make redirection-following optional, but default.

    connection, error = connect(request.headers["Host"], request.port)
    if !error.nil?
      p :error => error
      raise error
    end
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
      connection, error = connect(request.headers["Host"], request.port)
      # TODO(sissel): Do better error handling than raising.
      if !error.nil?
        p :error => error
        raise error
      end
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
  def connect(host, port)
    address = "#{host}:#{port}"
    @logger.debug("Fetching from pool", :address => address)
    error = nil
    connection = @pool.fetch(address) do
      @logger.info("New connection to #{address}")
      connection = FTW::Connection.new(address)
      error = connection.connect
      if !error.nil?
        # Return nil to the pool, so like, we failed..
        nil
      else
        # Otherwise return our new connection
        connection
      end
    end

    if !error.nil?
      @logger.error("Connection failed", :destination => address, :error => error)
      return nil, error
    end

    @logger.debug("Pool fetched a connection", :connection => connection)
    connection.mark
    return connection, nil
  end # def connect

  public(:initialize, :execute, :websocket!, :upgrade!)
end # class FTW::Agent
