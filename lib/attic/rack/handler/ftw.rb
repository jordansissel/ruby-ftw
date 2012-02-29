require "awesome_print"
require "rack"
require "ftw"
require "ftw/protocol"
require "ftw/crlf"
require "socket"

# THIS FILE HAS BEEN ABANDONED. PLEASE READ:
# FTW cannot run on Rack due to technical limitations in the Rack design,
# specifically:
#
# * rack.input must be buffered, to support IO#rewind, for the duration of each
#   request. This is not safe if that request is an HTTP Upgrade or a long
#   upload.
#
# As a result, this rack handler implementation has been abandoned.
# 
# The above decision is based on the response to this ticket:
#   https://github.com/rack/rack/issues/347
class Rack::Handler::FTW
  include FTW::Protocol
  include FTW::CRLF

  RACK_VERSION = [1,1]
  REQUEST_METHOD = "REQUEST_METHOD"
  SCRIPT_NAME = "SCRIPT_NAME"
  PATH_INFO = "PATH_INFO"
  QUERY_STRING = "QUERY_STRING"
  SERVER_NAME = "SERVER_NAME"
  SERVER_PORT = "SERVER_PORT"

  RACK_DOT_VERSION = "rack.version"
  RACK_DOT_URL_SCHEME = "rack.url_scheme"
  RACK_DOT_INPUT = "rack.input"
  RACK_DOT_ERRORS = "rack.errors"
  RACK_DOT_MULTITHREAD = "rack.multithread"
  RACK_DOT_MULTIPROCESS = "rack.multiprocess"
  RACK_DOT_RUN_ONCE = "rack.run_once"

  def self.run(app, config)
    server = self.new(app, config)
    server.run
  end

  private

  def initialize(app, config)
    @app = app
    @config = config
  end

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
    server = FTW::Server.new([@config[:Host], @config[:Port]].join(":"))
    server.each_connection do |connection|
      Thread.new do
        handle_connection(connection)
      end
    end
  end # def run

  def handle_connection(connection)
    while true
      begin
        request = read_http_message(connection)
        handle_request(request, connection)
      rescue => e
        puts e.inspect
        puts e.backtrace
        raise e
      end
    end
    connection.disconnect("Fun")
  end # def handle_connection

  def handle_request(request, connection)
    path, query = request.path.split("?", 2)
    env = {
      REQUEST_METHOD => request.method,
      SCRIPT_NAME => "/", # TODO(sissel): not totally sure what this really should be
      PATH_INFO => path,
      QUERY_STRING => query.nil? ? "" : query,
      SERVER_NAME => "???", # TODO(sissel): Set this
      SERVER_PORT => "who cares, really", # TODO(sissel): Set this
      RACK_DOT_VERSION => RACK_VERSION,
      RACK_DOT_URL_SCHEME =>  "http", # TODO(sissel): support https
      RACK_DOT_INPUT => connection,
      RACK_DOT_ERRORS => STDERR,
      RACK_DOT_MULTITHREAD => true,
      RACK_DOT_MULTIPROCESS => false,
      RACK_DOT_RUN_ONCE => false,
    }

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

    require "awesome_print"

    status, headers, body = @app.call(env)

    response = FTW::Response.new
    response.status = status.to_i
    response.version = request.version
    headers.each do |name, value|
      response.headers.add(name, value)
    end
    response.body = body

    connection.write(response.to_s + CRLF)
    body.each do |chunk|
      connection.write(chunk)
    end
    p :OK
  end # def handle_request

  public(:run, :initialize)
end
