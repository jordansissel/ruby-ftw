require "rack"
require "ftw"
require "ftw/protocol"
require "ftw/crlf"
require "socket"
require "cabin"

# FTW cannot fully respect the Rack 1.1 specification due to technical
# limitations in the Rack design, specifically:
#
# * rack.input must be buffered, to support IO#rewind, for the duration of each
#   request. This is not safe if that request is an HTTP Upgrade or a long
#   upload.
#
# FTW::Connection does not implement #rewind. Need it? File a ticket.
#
# To support HTTP Upgrade, CONNECT, and protocol-switching features, this
# server handler will set "ftw.connection" to the FTW::Connection related
# to this request.
#
# The above data is based on the response to this ticket:
#   https://github.com/rack/rack/issues/347
class Rack::Handler::FTW
  include FTW::Protocol
  include FTW::CRLF

  # The version of the rack specification supported by this handler.
  RACK_VERSION = [1,1]

  # A string constant value (used to avoid typos).
  REQUEST_METHOD = "REQUEST_METHOD".freeze
  # A string constant value (used to avoid typos).
  SCRIPT_NAME = "SCRIPT_NAME".freeze
  # A string constant value (used to avoid typos).
  PATH_INFO = "PATH_INFO".freeze
  # A string constant value (used to avoid typos).
  QUERY_STRING = "QUERY_STRING".freeze
  # A string constant value (used to avoid typos).
  SERVER_NAME = "SERVER_NAME".freeze
  # A string constant value (used to avoid typos).
  SERVER_PORT = "SERVER_PORT".freeze

  # A string constant value (used to avoid typos).
  RACK_DOT_VERSION = "rack.version".freeze
  # A string constant value (used to avoid typos).
  RACK_DOT_URL_SCHEME = "rack.url_scheme".freeze
  # A string constant value (used to avoid typos).
  RACK_DOT_INPUT = "rack.input".freeze
  # A string constant value (used to avoid typos).
  RACK_DOT_ERRORS = "rack.errors".freeze
  # A string constant value (used to avoid typos).
  RACK_DOT_MULTITHREAD = "rack.multithread".freeze
  # A string constant value (used to avoid typos).
  RACK_DOT_MULTIPROCESS = "rack.multiprocess".freeze
  # A string constant value (used to avoid typos).
  RACK_DOT_RUN_ONCE = "rack.run_once".freeze
  # A string constant value (used to avoid typos).
  RACK_DOT_LOGGER = "rack.logger".freeze
  # A string constant value (used to avoid typos).
  FTW_DOT_CONNECTION = "ftw.connection".freeze

  # This method is invoked when rack starts this as the server.
  def self.run(app, config)
    #@logger.subscribe(STDOUT)
    server = self.new(app, config)
    server.run
  end # def self.run

  private

  # setup a new rack server
  def initialize(app, config)
    @app = app
    @config = config
    @threads = []
  end # def initialize

  # Run the server.
  #
  # Connections are farmed out to threads.
  def run
    # {:environment=>"development", :pid=>nil, :Port=>9292, :Host=>"0.0.0.0",
    #  :AccessLog=>[], :config=>"/home/jls/projects/ruby-ftw/examples/test.ru",
    #  :server=>"FTW"}
    #
    # listen, pass connections off
    #
    # 
    # """A Rack application is an Ruby object (not a class) that responds to
    # call.  It takes exactly one argument, the environment and returns an
    # Array of exactly three values: The status, the headers, and the body."""
    #
    logger.info("Starting server", :config => @config)
    @server = FTW::Server.new([@config[:Host], @config[:Port]].join(":"))
    @server.each_connection do |connection|
      # The rack specification insists that 'rack.input' objects support
      # #rewind. Bleh. Just lie about it and monkeypatch it in.
      # This is required for Sinatra to accept 'post' requests, otherwise
      # it barfs.
      class << connection
        def rewind(*args)
          # lolrack, nothing to do here.
        end
      end

      @threads << Thread.new do
        handle_connection(connection)
      end
    end
  end # def run

  def stop
    @server.stop unless @server.nil?
    @threads.each(&:join)
  end # def stop

  # Handle a new connection.
  #
  # This method parses http requests and passes them on to #handle_request
  #
  # @param connection The FTW::Connection being handled.
  def handle_connection(connection)
    while true
      begin
        request = read_http_message(connection)
      rescue IOError, EOFError, Errno::EPIPE, Errno::ECONNRESET, HTTP::Parser::Error
        # Connection EOF'd or errored before we finished reading a full HTTP
        # message, shut it down.
        break
      rescue ArgumentError
        # Invalid http request sent
        break
      end

      begin
        handle_request(request, connection)
      rescue => e
        puts e.inspect
        puts e.backtrace
        raise e
      end
    end
  ensure
    connection.disconnect("Closing...")
  end # def handle_connection

  # Handle a request. This will set up the rack 'env' and invoke the
  # application associated with this handler.
  def handle_request(request, connection)
    path, query = request.path.split("?", 2)
    env = {
      # CGI-like environment as required by the Rack SPEC version 1.1
      REQUEST_METHOD => request.method,
      SCRIPT_NAME => "/", # TODO(sissel): not totally sure what this really should be
      PATH_INFO => path,
      QUERY_STRING => query.nil? ? "" : query,
      SERVER_NAME => "hahaha, no", # TODO(sissel): Set this
      SERVER_PORT => "", # TODO(sissel): Set this

      # Rack-specific environment, also required by Rack SPEC version 1.1
      RACK_DOT_VERSION => RACK_VERSION,
      RACK_DOT_URL_SCHEME =>  "http", # TODO(sissel): support https
      RACK_DOT_INPUT => connection,
      RACK_DOT_ERRORS => STDERR,
      RACK_DOT_MULTITHREAD => true,
      RACK_DOT_MULTIPROCESS => false,
      RACK_DOT_RUN_ONCE => false,
      RACK_DOT_LOGGER => logger,

      # Extensions, not in Rack v1.1. 

      # ftw.connection lets you access the connection involved in this request.
      # It should be used when you need to hijack the connection for use
      # in proxying, HTTP CONNECT, websockets, SPDY(maybe?), etc.
      FTW_DOT_CONNECTION => connection
    } # env

    request.headers.each do |name, value|
      # The Rack spec says: 
      # """ Variables corresponding to the client-supplied HTTP request headers
      #     (i.e., variables whose names begin with HTTP_). The presence or
      #     absence of these variables should correspond with the presence or
      #     absence of the appropriate HTTP header in the request. """
      #
      # It doesn't specify how to translate the header names into this hash syntax.
      # I looked at what Thin does, and it capitalizes and replaces dashes with 
      # underscores, so I'll just copy that behavior. The specific code that implements
      # this in thin is here:
      # https://github.com/macournoyer/thin/blob/2e9db13e414ae7425/ext/thin_parser/thin.c#L89-L95
      #
      # The Rack spec also doesn't describe what should be done for headers
      # with multiple values.
      #
      env["HTTP_#{name.upcase.gsub("-", "_")}"] = value
    end # request.headers.each

    # Invoke the application in this rack app
    status, headers, body = @app.call(env)

    # The application is done handling this request, respond to the client.
    response = FTW::Response.new
    response.status = status.to_i
    response.version = request.version
    headers.each do |name, value|
      response.headers.add(name, value)
    end
    response.body = body

    begin
      connection.write(response.to_s + CRLF)
      write_http_body(body, connection, response["Transfer-Encoding"] == "chunked")
    rescue => e
      @logger.error(e)
      connection.disconnect(e.inspect)
    end
  end # def handle_request

  # Get the logger.
  def logger
    if @logger.nil?
      @logger = Cabin::Channel.get
    end
    return @logger
  end # def logger

  public(:run, :initialize, :stop)
end
