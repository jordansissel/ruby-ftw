require "cabin" # rubygem "cabin"
require "net/ftw/dns"
require "net/ftw/namespace"
require "socket"
require "timeout" # ruby stdlib, just for the Timeout exception.
require "backport-bij" # for Array#rotate, IO::WaitWritable, etc, in ruby < 1.9

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

# A network connection. This is TCP.
#
# Example:
#
#     conn = Net::FTW::Connection.new("www.google.com:80")
#     conn.on(CONNECTED) do |address| 
#       puts "Connected to #{address} (#{conn.peer})"
#       conn.write("GET / HTTP/1.0\r\n\r\n")
#     end
#     conn.on(DATA) do |data|
#       puts data
#     end
#     conn.run
#
# You can use IO::select on this objects of this type.
class Net::FTW::Connection

  # Events
  CONNECTED = :connected
  DISCONNECTED = :disconnected
  READER_CLOSED = :reader_closed
  DATA = :data

  # Disconnection reasons
  TIMEOUT = :timeout
  REFUSED = :refused
  LOST = :lost
  INTENTIONAL = :intentional

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
  public
  def initialize(destinations)
    if destinations.is_a?(String)
      @destinations = [destinations]
    else
      @destinations = destinations
    end

    # Handlers are key => array of callbacks
    @handlers = Hash.new { |h,k| h[k] = [] }

    on(CONNECTED) { |address| connected(address) }
    on(DISCONNECTED) { |reason, error| disconnected(reason, error) }
    #on(READER_CLOSED) { @reader_closed = true }

    @connect_timeout = 2

    # Use a fixed-size string that we set to BINARY encoding.
    # Not all byte sequences are UTF-8 friendly :0
    @read_size = 16384
    @read_buffer = " " * @read_size

    # Tell Ruby 1.9 that this string is a binary string, not utf-8 or somesuch.
    if @read_buffer.respond_to?(:force_encoding)
      @read_buffer.force_encoding("BINARY")
    end

    # TODO(sissel): Validate @destinations
  end # def initialize

  # Register an event callback
  # Valid events:
  #
  # * Net::FTW::Connection::CONNECTED - 1 argument, the host:port string connected to.
  # * Net::FTW::Connection::DISCONNECTED - 2 arguments, the reason and the
  #   exception (if any)
  # * Net::FTW::Connection::DATA - 1 argument to block, the data read
  #
  # Disconnection reasons:
  #   * :timeout
  #   * :refused
  #   * :closed
  #   * :lost
  public
  def on(event, &block)
    @handlers[event] << block
  end # def on

  # Trigger an event with arguments.
  # All callbacks for the event will be invoked in the order they were
  # registered. See the 'on' method for registering callbacks.
  public
  def trigger(event, *args)
    @handlers[event].each do |block|
      block.call(*args)
    end
  end # def trigger

  public
  def connect(timeout=nil)
    # TODO(sissel): Raise if we're already connected?
    close if connected?
    host, port = @destinations.first.split(":")
    @destinations = @destinations.rotate # round-robin

    # Do dns resolution on the host. If there are multiple
    # addresses resolved, return one at random.
    @remote_address = Net::FTW::DNS.singleton.resolve_random(host)

    family = @remote_address.include?(":") ? Socket::AF_INET6 : Socket::AF_INET
    @socket = Socket.new(family, Socket::SOCK_STREAM, 0)
    sockaddr = Socket.pack_sockaddr_in(port, @remote_address)
    # TODO(sissel): Support local address binding

    # Connect with timeout
    begin
      @socket.connect_nonblock(sockaddr)
    rescue IO::WaitWritable
      # Ruby actually raises Errno::EINPROGRESS, but for some reason
      # the documentation says to use this IO::WaitWritable thing...
      # I don't get it, but whatever :(
      if writable?(timeout)
        begin
          @socket.connect_nonblock(sockaddr) # check connection failure
        rescue Errno::EISCONN # Ignore, we're already connected.
        rescue Errno::ECONNREFUSED => e
          # Fire 'disconnected' event with reason :refused
          trigger(DISCONNECTED, :refused, e)
        end
      else
        # Connection timeout
        # Fire 'disconnected' event with reason :timeout
          trigger(DISCONNECTED, :connect_timeout, nil)
      end
    end

    # We're now connected.
    trigger(CONNECTED, "#{host}:#{port}")
  end # def connect

  # Is this Connection connected?
  public
  def connected?
    return @connected
  end # def connected?

  # Write data to this connection.
  # This method blocks until the write succeeds unless a timeout is given.
  #
  # Returns the number of bytes written (See IO#syswrite)
  public
  def write(data, timeout=nil)
    #connect if !connected?
    if writable?(timeout)
      return @socket.syswrite(data)
    else
      raise Timeout::Error.new
    end
  end # def write

  # Read data from this connection
  # This method blocks until the read succeeds unless a timeout is given.
  #
  # This method is not guaranteed to read exactly 'length' bytes. See
  # IO#sysread
  public
  def read(length, timeout=nil)
    if readable?(timeout)
      begin
        @socket.sysread(length, @read_buffer)
        return @read_buffer
      rescue EOFError
        trigger(READER_CLOSED)
      end
    else
      raise Timeout::Error.new
    end
  end # def read

  # End this connection
  public
  def disconnect(reason=INTENTIONAL)
    begin 
      #@reader_closed = true
      @socket.close_read
    rescue IOError => e
      # Ignore
    end

    begin 
      @socket.close_write
    rescue IOError => e
      # Ignore
    end

    trigger(DISCONNECTED, reason)
  end # def disconnect

  # Is this connection writable? Returns true if it is writable within
  # the timeout period. False otherwise.
  #
  # The time out is in seconds. Fractional seconds are OK.
  public
  def writable?(timeout)
    ready = IO.select(nil, [@socket], nil, timeout)
    return !ready.nil?
  end # def writable?

  # Is this connection readable? Returns true if it is readable within
  # the timeout period. False otherwise.
  #
  # The time out is in seconds. Fractional seconds are OK.
  public
  def readable?(timeout)
    #return false if @reader_closed
    ready = IO.select([@socket], nil, nil, timeout)
    return !ready.nil?
  end # def readable?

  protected
  def connected(address)
    @remote_address = nil
    @connected = true
  end # def connected

  protected
  def disconnected(reason, error)
    @remote_address = nil
    @connected = false
  end # def disconnected

  # The host:port
  public
  def peer
    return @remote_address
  end # def peer

  # Run this Connection.
  # This is generally meant for Threaded or synchronous operation. 
  # For EventMachine, see TODO(sissel): Implement EventMachine support.
  public
  def run
    connect(@connect_timeout) if not connected?
    while connected?
      read_and_trigger
    end
  end # def run

  # Read data and trigger data callbacks.
  #
  # This is mainly useful if you are implementing your own run loops
  # and IO::select shenanigans.
  public
  def read_and_trigger
    data = read(@read_size)
    if data.length == 0
      disconnect(EOFError)
    else
      trigger(DATA, data)
    end
  end # def read_and_trigger

  # Support 'to_io' so you can use IO::select on this object.
  public
  def to_io
    return @socket
  end
end # class Net::FTW::Connection

