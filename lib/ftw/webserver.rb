require "ftw"
require "ftw/protocol"
require "ftw/crlf"
require "socket"
require "cabin"

# An attempt to invent a simple FTW web server.
class FTW::WebServer
  include FTW::Protocol
  include FTW::CRLF

  def initialize(host, port, &block)
    @host = host
    @port = port
    @handler = block

    @logger = Cabin::Channel.get
    @threads = []
  end # def initialize

  # Run the server.
  #
  # Connections are farmed out to threads.
  def run
    logger.info("Starting server", :config => @config)
    @server = FTW::Server.new([@host, @port].join(":"))
    @server.each_connection do |connection|
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
      rescue EOFError, Errno::EPIPE, Errno::ECONNRESET, HTTP::Parser::Error, IOError
        # Connection EOF'd or errored before we finished reading a full HTTP
        # message, shut it down.
        break
      end

      if request["Content-Length"] || request["Transfer-Encoding"]
        request.body = connection
      end

      begin
        handle_request(request, connection)
      rescue => e
        puts e.inspect
        puts e.backtrace
        raise e
      end
    end
    connection.disconnect("Fun")
  end # def handle_connection

  # Handle a request. This will set up the rack 'env' and invoke the
  # application associated with this handler.
  def handle_request(request, connection)
    response = FTW::Response.new
    response.version = request.version
    response["Connection"] = request.headers["Connection"] || "close"

    # Process this request with the handler
    @handler.call(request, response, connection)

    # Write the response
    begin
      connection.write(response.to_s + CRLF)
      if response.body?
        write_http_body(response.body, connection,
                        response["Transfer-Encoding"] == "chunked") 
      end
    rescue => e
      @logger.error(e)
      connection.disconnect(e.inspect)
    end

    if response["Connection"] == "close" or response["Connection"].nil?
      connection.disconnect("'Connection' header was close or nil")
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
end # class FTW::WebServer
