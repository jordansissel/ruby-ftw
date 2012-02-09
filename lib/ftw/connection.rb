require "cabin" # rubygem "cabin"
require "ftw/dns"
require "ftw/poolable"
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
  include FTW::Poolable

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

    @logger = Cabin::Channel.get($0)
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

    @logger.debug("Connecting", :address => @remote_address,
                  :host => host, :port => port)

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
    have_pushback = !@pushback_buffer.empty?
    if have_pushback
      data << @pushback_buffer
      @pushback_buffer = ""
      # We have data 'now' so don't wait.
      timeout = 0
    end

    if readable?(timeout)
      begin
        @socket.sysread(@read_size, @read_buffer)
        data << @read_buffer
        return data
      rescue EOFError => e
        raise e
      end
    else
      if have_pushback
        return data
      else
        raise ReadTimeout.new
      end
    end
  end # def read

  # Push back some data onto the connection's read buffer.
  public
  def pushback(data)
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

  # Support 'to_io' so you can use IO::select on this object.
  public
  def to_io
    return @socket
  end # def to_io

  # def inspect
  public
  def inspect
    return "<#{self.class.name} destinations=#{@destinations.inspect}>"
  end # def inspect
  alias_method :inspect, :to_s

  # Secure this connection with TLS.
  public
  def secure(timeout=nil, options={})
    # Skip this if we're already secure.
    return if secured?

    @logger.debug("Securing this connection", :peer => peer, :connection => self)
    # Wrap this connection with TLS/SSL
    require "openssl"
    sslcontext = OpenSSL::SSL::SSLContext.new
    sslcontext.ssl_version = :TLSv1
    # If you use VERIFY_NONE, you are removing an important piece 
    sslcontext.verify_mode = OpenSSL::SSL::VERIFY_PEER
    # TODO(sissel): Try to be smart about setting this default.
    sslcontext.ca_path = "/etc/ssl/certs"
    logit = lambda { |what| proc { |*args| @logger.info(what, :args => args) } }
    sslcontext.methods.grep(/_cb=/).each do |what|
      sslcontext.send("#{what}", logit.call(what))
    end
    @socket = OpenSSL::SSL::SSLSocket.new(@socket, sslcontext)

    # SSLSocket#connect_nonblock will do the SSL/TLS handshake.
    # TODO(sissel): refactor this into a method that both secure and connect
    # methods can call.
    start = Time.now
    begin
      @socket.connect_nonblock
    rescue IO::WaitReadable, IO::WaitWritable
      # The ruby OpenSSL docs for 1.9.3 have example code saying I should use
      # IO::WaitReadable, but in the real world it raises an SSLError with
      # a specific string message instead of Errno::EAGAIN or IO::WaitReadable
      # explicitly...
      #
      # This SSLSocket#connect_nonblock raising WaitReadable (Technically,
      # OpenSSL::SSL::SSLError) is in contrast to what Socket#connect_nonblock
      # raises, WaitWritable (ok, Errno::EINPROGRESS, technically)
      # Ruby's SSL exception for 'this call would block' is pretty shitty.
      #
      # If the exception string is *not* 'read would block' we have a real
      # problem.
      #if e.to_s != "read would block"
        #raise e
      #end
      
      if !timeout.nil?
        time_left = timeout - (Time.now - start)
        raise ConnectTimeout.new if time_left < 0
        r, w, e = IO.select([@socket], [@socket], nil, time_left)
      else
        r, w, e = IO.select([@socket], [@socket], nil, timeout)
      end

      # try connect_nonblock again if the socket is ready
      retry if r.size > 0 || w.size > 0
      # otherwise, timed out.
    end

    @secure = true
  end # def secure

  # Has this connection been secured?
  public
  def secured?
    return @secure
  end # def secured?

end # class FTW::Connection

