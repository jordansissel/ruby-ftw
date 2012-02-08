require "cabin" # rubygem "cabin"
require "ftw/dns"
require "ftw/namespace"
require "socket"
require "timeout" # ruby stdlib, just for the Timeout exception.
require "backport-bij" # for Array#rotate, IO::WaitWritable, etc, in ruby < 1.9

# A network connection. This is TCP.
#
# You can use IO::select on this objects of this type.
# (at least, in MRI you can)
class FTW::Connection
  class ConnectTimeout < StandardError; end
  class ReadTimeout < StandardError; end

  # A new network connection.
  # The 'destination' argument can be an array of strings or a single string.
  # String format is expected to be "host:port"
  #
  # Example:
  #
  #     conn = FTW::Connection.new(["1.2.3.4:80", "1.2.3.5:80"])
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

    @connect_timeout = 2

    # Use a fixed-size string that we set to BINARY encoding.
    # Not all byte sequences are UTF-8 friendly :0
    @read_size = 16384
    @read_buffer = " " * @read_size
    @pushback_buffer = ""

    # Tell Ruby 1.9 that this string is a binary string, not utf-8 or somesuch.
    if @read_buffer.respond_to?(:force_encoding)
      @read_buffer.force_encoding("BINARY")
    end

    # TODO(sissel): Validate @destinations
    # TODO(sissel): Barf if a destination is not of the form "host:port"
  end # def initialize

  public
  def connect(timeout=nil)
    # TODO(sissel): Raise if we're already connected?
    close if connected?
    host, port = @destinations.first.split(":")
    @destinations = @destinations.rotate # round-robin

    # Do dns resolution on the host. If there are multiple
    # addresses resolved, return one at random.
    @remote_address = FTW::DNS.singleton.resolve_random(host)

    # Addresses with colon ':' in them are assumed to be IPv6
    family = @remote_address.include?(":") ? Socket::AF_INET6 : Socket::AF_INET
    @socket = Socket.new(family, Socket::SOCK_STREAM, 0)

    # This api is terrible. pack_sockaddr_in? This isn't C, man...
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
        rescue Errno::EISCONN 
          # Ignore, we're already connected.
        rescue Errno::ECONNREFUSED => e
          # Fire 'disconnected' event with reason :refused
          return e
        end
      else
        # Connection timeout
        # Fire 'disconnected' event with reason :timeout
        return ConnectTimeout.new
      end
    end

    # We're now connected.
    return true
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
  def read(timeout=nil)
    data = ""
    data.force_encoding("BINARY") if data.respond_to?(:force_encoding)
    if !@pushback_buffer.empty?
      data += @pushback_buffer
      @pushback_buffer = ""
      # Don't block indefinitely since we know we have data right now.
      timeout = 0 if timeout == nil
    end

    if readable?(timeout)
      begin
        @socket.sysread(@read_size, @read_buffer)
        data += @read_buffer
        return data
      rescue EOFError
        trigger(READER_CLOSED)
      end
    else
      raise ReadTimeout.new
    end
  end # def read

  # Push back some data onto the connection's read buffer.
  public
  def pushback(data)
    p :pushback => data[0..10]  + "..." + data[-10 .. -1]
    @pushback_buffer << data
  end # def pushback

  # End this connection, specifying why.
  public
  def disconnect(reason)
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
  end # def to_io

  alias_method :inspect, :to_s

  public
  def inspect
    return "#{self.class.name} <destinations=#{@destinations.inspect}>"
  end # def inspect
end # class FTW::Connection

