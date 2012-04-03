require "ftw/namespace"
require "ftw/request"
require "ftw/connection"
require "ftw/protocol"
require "ftw/pool"
require "ftw/websocket"
require "addressable/uri"
require "cabin"
require "openssl"

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
  include FTW::Protocol
  require "ftw/agent/configuration"
  include FTW::Agent::Configuration

  # Thrown when too many redirects are encountered
  # See also {FTW::Agent::Configuration::REDIRECTION_LIMIT}
  class TooManyRedirects < StandardError
    attr_accessor :response
    def initialize(reason, response)
      super(reason)
      @response = response
    end
  end

  # List of standard HTTP methods described in RFC2616
  STANDARD_METHODS = %w(options get head post put delete trace connect)

  # Everything is private by default.
  # At the bottom of this class, public methods will be declared.
  private

  def initialize
    @pool = FTW::Pool.new
    @logger = Cabin::Channel.get

    configuration[REDIRECTION_LIMIT] = 20

    @certificate_store = OpenSSL::X509::Store.new
    @certificate_store.add_file("/etc/ssl/certs/ca-bundle.trust.crt")
    @certificate_store.verify_callback = proc do |*args|
      p :verify_callback => args
      true
    end

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

    if options.include?(:body)
      request.body = options[:body]
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

    if request.protocol == "https"
      connection.secure(:certificate_store => @certificate_store)
    end
    response = request.execute(connection)

    redirects = 0
    # Follow redirects
    while response.redirect? and response.headers.include?("Location")
      # RFC2616 section 10.3.3 indicates HEAD redirects must not include a
      # body. Otherwise, the redirect response can have a body, so let's
      # throw it away.
      if request.method == "HEAD" 
        # Head requests have no body
        connection.release
      elsif response.content?
        # Throw away the body
        response.body = connection
        # read_body will consume the body and release this connection
        response.read_body { |chunk| }
      end

      # TODO(sissel): If this response has any cookies, store them in the
      # agent's cookie store

      redirects += 1
      if redirects > configuration[REDIRECTION_LIMIT]
        # TODO(sissel): include original a useful debugging information like
        # the trace of redirections, etc.
        raise TooManyRedirects.new("Redirect more than " \
            "#{configuration[REDIRECTION_LIMIT]} times, aborting.", response)
        # I don't like this api from FTW::Agent. I think 'get' and other methods
        # should return (object, error), and if there's an error 
      end

      @logger.debug("Redirecting", :location => response.headers["Location"])
      request.use_uri(response.headers["Location"])
      connection, error = connect(request.headers["Host"], request.port)
      # TODO(sissel): Do better error handling than raising.
      if !error.nil?
        p :error => error
        raise error
      end
      if request.protocol == "https"
        connection.secure(:certificate_store => @certificate_store)
      end
      response = request.execute(connection)
    end # while being redirected

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

  # shutdown this agent.
  #
  # This will shutdown all active connections.
  def shutdown
    @pool.each do |identifier, list|
      list.each do |connection|
        connection.disconnect("stopping agent")
      end
    end
  end # def shutdown

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

  # TODO(sissel): Implement methods for managing the certificate store
  # TODO(sissel): Implement methods for managing the cookie store
  # TODO(sissel): Implement methods for managing the cache
  # TODO(sissel): Implement configuration stuff? Is FTW::Agent::Configuration the best way?
  public(:initialize, :execute, :websocket!, :upgrade!, :shutdown)
end # class FTW::Agent
