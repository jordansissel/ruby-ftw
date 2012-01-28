require "cabin" # rubygem "cabin"
require "fcntl"
require "net/ftw/dns"
require "net/ftw/namespace"
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

    @connect_timeout = 2
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

  def trigger(event, *args)
    @handlers[event].each do |block|
      block.call(*args)
    end
  end # def trigger

  def connect
    close if connected?
    host, port = @destinations.first.split(":")
    @destinations = @destinations.rotate # round-robin

    # Do dns resolution on the host. If there are multiple
    # addresses resolved, return one at random.
    @remote_address = Net::FTW::DNS.singleton.resolve_random(host)

    family = @remote_address.include?(":") ? Socket::AF_INET6 : Socket::AF_INET
    @socket = Socket.new(family, Socket::SOCK_STREAM, 0)
    sockaddr = Socket.pack_sockaddr_in(port, @remote_address)

    # Connect with timeout
    begin
      @socket.connect_nonblock(sockaddr)
    rescue IO::WaitWritable
      # Ruby actually raises Errno::EINPROGRESS, but for some reason
      # the documentation says to use this IO::WaitWritable thing...
      # I don't get it, but whatever :(
      if writable?(@connect_timeout)
        begin
          @socket.connect_nonblock(sockaddr) # check connection failure
        rescue Errno::EISCONN # Ignore, we're already connected.
        rescue Errno::ECONNREFUSED
          # Fire 'disconnected' event with reason :refused
          trigger(:disconnected, :refused)
        end
      else
        # Connection timeout
        # Fire 'disconnected' event with reason :timeout
          trigger(:disconnected, :connect_timeout)
      end
    end

    trigger(:connected, "#{host}:#{port}"
    # Fire the 'connected' event
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

  # Is this connection writable? Returns true if it is writable within
  # the timeout period. False otherwise.
  #
  # The time out is in seconds. Fractional seconds are OK.
  def writable?(timeout)
    ready = IO.select(nil, [@socket], nil, timeout)
    return !ready.nil?
  end # def writable?

  # Is this connection readable? Returns true if it is readable within
  # the timeout period. False otherwise.
  #
  # The time out is in seconds. Fractional seconds are OK.
  def readable?(timeout)
    ready = IO.select([@socket], nil, nil, timeout)
    return !ready.nil?
  end # def readable?

  # Allow setting the 'connected' callback
  #def connected=(&block)
    #define_method(:connected, &block)
  #end # def connected=

end # class Net::FTW::Connection

