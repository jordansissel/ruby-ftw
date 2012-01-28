require "net/ftw/namespace"
require "net/ftw/dns"
require "socket"

# TODO(sissel): What's the API look like here?
# EventMachine::Connection has these:
#   * events: post_init (and connection_completed), receive_data, unbind
#   * methods: send_data
#
# Actual events:
#   * connected
#   * disconnected(reason)
#     * timeout, connection reset, connection refused, write error, read
#        error, etc
#   * data received
#
# Methods
#   * send data
#   * reconnect
#   * get socket
#   * disconnect
#

class Net::FTW::Connection
  # A new network connection.
  # The 'destination' argument can be an array of strings or a single string.
  # String format is expected to be "host:port"
  #
  # Example:
  #
  #     conn = Net::FTW::Connection.new(["1.2.3.4:80", "1.2.3.5:80"])
  #
  # If you specify multiple destinations, they are used in a round-robin
  # decision made during reconnection.
  def initialize(destinations)
    if destinations.is_a?(String)
      @destinations = [destinations]
    else
      @destinations = destinations
    end

    # Handlers are key => array of callbacks
    @handlers = Hash.new { |h,k| h[k] = [] }

    # TODO(sissel): Validate @destinations
  end # def initialize

  # Register an event callback
  # Valid events:
  #
  # * :connected - no arguments to block
  # * :disconnected - 1 argument to block, the reason for disconnect
  # * :data - 1 argument to block, the data read
  def on(event, &block)
    @handlers[event] << block
  end # def on

  def connect
    close if connected?
    host, port = @destinations.first.split(":")
    @destinations = @destinations.rotate # round-robin

    # If the host appears to be a hostname, do dns resolution
    # If there are multiple A or AAAA records, pick one at random.
    # TODO(sissel): How should we know to do v4 or v6 connections?
    @socket = TCPSocket.new(host, port)

    begin # emulate blocking connect
      socket.connect_nonblock(sockaddr)
    rescue IO::WaitWritable
      IO.select(nil, [socket]) # wait 3-way handshake completion
      begin
        socket.connect_nonblock(sockaddr) # check connection failure
      rescue Errno::EISCONN
      end
    end

    @connected = true
  end # def connect

  def connected?
    return @connected
  end # def connected?

  # Write data to this connection.
  # This will connect to a destination if it is not already connected.
  def write(data)
    connect if !connected?
    @socket.write(data)
  end # def write

  # Allow setting the 'connected' callback
  #def connected=(&block)
    #define_method(:connected, &block)
  #end # def connected=

end # class Net::FTW::Connection

