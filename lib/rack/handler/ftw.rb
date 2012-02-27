require "awesome_print"
require "rack"
require "ftw"
require "socket"

class Rack::Handler::FTW
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
    server = TCPServer.new(@config[:Host], @config[:Port])
    loop do
      client = server.accept
      Thread.new do
        handle(client)
      end
    end
  end # def run

  def handle(socket)
    connection = ::FTW::Connection.from_io(socket, :server)
    p connection
    connection.secure
    p :OK
    connection.write("Hello")
    connection.disconnect("Fun")
  end # def handle

  public(:run, :initialize)
end
