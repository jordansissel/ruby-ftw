require "cabin" # rubygem "cabin"
require "ftw/dns"
require "ftw/poolable"
require "ftw/namespace"
require "socket"
require "timeout" # ruby stdlib, just for the Timeout exception.

if RUBY_VERSION =~ /^1\.8/
  # for Array#rotate, IO::WaitWritable, etc, in ruby < 1.9
  require "backports"
end

require "openssl"

# A network connection. This is TCP.
#
# You can use IO::select on this objects of this type.
# (at least, in MRI you can)
#
# You can activate SSL/TLS on this connection by invoking FTW::Connection#secure
#
# This class also implements buffering itself because some IO-like classes
# (OpenSSL::SSL::SSLSocket) do not support IO#ungetbyte
class FTW::Connection
  include FTW::Poolable
  include Cabin::Inspectable

  # A connection attempt timed out
  class ConnectTimeout < StandardError; end
  
  # A connection attempt was rejected
  class ConnectRefused < StandardError; end

  # A read timed out
  class ReadTimeout < StandardError; end

  # A write timed out
  class WriteTimeout < StandardError; end

  # Secure setup timed out
  class SecureHandshakeTimeout < StandardError; end

  private

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
  def initialize(destinations)
    if destinations.is_a?(String)
      @destinations = [destinations]
    else
      @destinations = destinations
    end

    @mode = :client
    setup
  end # def initialize

  # Set up this connection.
  def setup
    @logger = Cabin::Channel.get
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

    @inspectables = [:@destinations, :@connected, :@remote_address, :@secure]
    @connected = false
    @remote_address = nil
    @secure = false

    # TODO(sissel): Validate @destinations
    # TODO(sissel): Barf if a destination is not of the form "host:port"
  end # def setup

  # Create a new connection from an existing IO instance (like a socket)
  # 
  # Valid modes are :server and :client.
  #
  # * specify :server if this connection is from a server (via Socket#accept)
  # * specify :client if this connection is from a client (via Socket#connect)
  def self.from_io(io, mode=:server)
    valid_modes = [:server, :client]
    if !valid_modes.include?(mode)
      raise InvalidArgument.new("Invalid connection mode '#{mode}'. Valid modes: #{valid_modes.inspect}")
    end

    connection = self.new(nil) # New connection with no destinations
    connection.instance_eval do
      @socket = io
      @connected = true
      port, address = Socket.unpack_sockaddr_in(io.getpeername)
      @remote_address = "#{address}:#{port}"
      @mode = mode
    end
    return connection
  end # def self.from_io

  # Connect now.
  #
  # Timeout value is optional. If no timeout is given, this method
  # blocks until a connection is successful or an error occurs.
  #
  # You should check the return value of this method to determine if
  # a connection was successful.
  #
  # Possible return values are on error include:
  #
  # * FTW::Connection::ConnectRefused
  # * FTW::Connection::ConnectTimeout
  #
  # @return [nil] if the connection was successful
  # @return [StandardError or subclass] if the connection failed
  def connect(timeout=nil)
    # TODO(sissel): Raise if we're already connected?
    disconnect("reconnecting") if connected?
    host, port = @destinations.first.split(":")
    @destinations = @destinations.rotate # round-robin

    # Do dns resolution on the host. If there are multiple
    # addresses resolved, return one at random.
    addresses = FTW::DNS.singleton.resolve(host)

    addresses.each do |address|
      # Try each address until one works.
      @remote_address = address
      # Addresses with colon ':' in them are assumed to be IPv6
      family = @remote_address.include?(":") ? Socket::AF_INET6 : Socket::AF_INET
      @logger.debug("Connecting", :address => @remote_address,
                    :host => host, :port => port, :family => family)
      @socket = Socket.new(family, Socket::SOCK_STREAM, 0)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # This api is terrible. pack_sockaddr_in? This isn't C, man...
      @logger.debug("packing", :data => [port.to_i, @remote_address])
      sockaddr = Socket.pack_sockaddr_in(port.to_i, @remote_address)
      # TODO(sissel): Support local address binding

      # Connect with timeout
      begin
        @socket.connect_nonblock(sockaddr)
      rescue IO::WaitWritable, Errno::EINPROGRESS
        # Ruby actually raises Errno::EINPROGRESS, but for some reason
        # the documentation says to use this IO::WaitWritable thing...
        # I don't get it, but whatever :(

        writable = writable?(timeout)

        # http://jira.codehaus.org/browse/JRUBY-6528; IO.select doesn't behave
        # correctly on JRuby < 1.7, so work around it.
        if writable || (RUBY_PLATFORM == "java" and JRUBY_VERSION < "1.7.0")
          begin
            @socket.connect_nonblock(sockaddr) # check connection failure
          rescue Errno::EISCONN 
            # Ignore, we're already connected.
          rescue Errno::ECONNREFUSED => e
            # Fire 'disconnected' event with reason :refused
            @socket.close
            return ConnectRefused.new("#{host}[#{@remote_address}]:#{port}")
          rescue Errno::ETIMEDOUT
            # This occurs when the system's TCP timeout hits, we have no
            # control over this, as far as I can tell. *maybe* setsockopt(2)
            # has a flag for this, but I haven't checked..
            # TODO(sissel): We should instead do 'retry' unless we've exceeded
            # the timeout.
            @socket.close
            return ConnectTimeout.new("#{host}[#{@remote_address}]:#{port}")
          rescue Errno::EINPROGRESS
            # If we get here, it's likely JRuby version < 1.7.0. EINPROGRESS at
            # this point in the code means that we have timed out.
            @socket.close
            return ConnectTimeout.new("#{host}[#{@remote_address}]:#{port}")
          end
        else
          # Connection timeout;
          return ConnectTimeout.new("#{host}[#{@remote_address}]:#{port}")
        end

        # If no error at this point, we're now connected.
        @connected = true
        break
      end # addresses.each
    end 
    return nil
  end # def connect

  # Is this Connection connected?
  def connected?
    return @connected
  end # def connected?

  # Write data to this connection.
  # This method blocks until the write succeeds unless a timeout is given.
  #
  # This method is not guaranteed to have written the full data given.
  #
  # Returns the number of bytes written (See also IO#syswrite)
  def write(data, timeout=nil)
    #connect if !connected?
    if writable?(timeout)
      return @socket.syswrite(data)
    else
      raise FTW::Connection::WriteTimeout.new(self.inspect)
    end
  end # def write

  # Read data from this connection
  # This method blocks until the read succeeds unless a timeout is given.
  #
  # This method is not guaranteed to read exactly 'length' bytes. See
  # IO#sysread
  def read(length=16384, timeout=nil)
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
        # Read at most 'length' data, so read less from the socket
        # We'll read less than 'length' if the pushback buffer has
        # data in it already.
        @socket.sysread(length - data.length, @read_buffer)
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
  def pushback(data)
    @pushback_buffer << data
  end # def pushback

  # End this connection, specifying why.
  def disconnect(reason)
    if @socket.is_a?(OpenSSL::SSL::SSLSocket)
      @socket.sysclose()
    else
      begin 
        @socket.close_read
      rescue IOError => e
        # Ignore, perhaps we shouldn't ignore.
      end

      begin 
        @socket.close_write
      rescue IOError => e
        # Ignore, perhaps we shouldn't ignore.
      end
    end
  end # def disconnect

  # Is this connection writable? Returns true if it is writable within
  # the timeout period. False otherwise.
  #
  # The time out is in seconds. Fractional seconds are OK.
  def writable?(timeout)
    readable, writable, errors = IO.select(nil, [@socket], nil, timeout)
    return !writable.nil?
  end # def writable?

  # Is this connection readable? Returns true if it is readable within
  # the timeout period. False otherwise.
  #
  # The time out is in seconds. Fractional seconds are OK.
  def readable?(timeout)
    readable, writable, errors = IO.select([@socket], nil, nil, timeout)
    return !readable.nil?
  end # def readable?

  # The host:port
  def peer
    return @remote_address
  end # def peer

  # Support 'to_io' so you can use IO::select on this object.
  def to_io
    return @socket
  end # def to_io

  # Secure this connection with TLS.
  #
  # Options:
  #
  # * :certificate_store, an OpenSSL::X509::Store
  # * :timeout, a timeout threshold in seconds.
  def secure(options=nil)
    # Skip this if we're already secure.
    return if secured?

    defaults = {
      :timeout => nil,
      #:certificate_store => OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE
    }
    settings = defaults.merge(options) unless options.nil?

    @logger.info("Securing this connection", :peer => peer, :options => settings)
    # Wrap this connection with TLS/SSL
    sslcontext = OpenSSL::SSL::SSLContext.new
    # If you use VERIFY_NONE, you are removing the trust feature of TLS. Don't do that.
    # Encryption without trust means you don't know who you are talking to.
    sslcontext.verify_mode = OpenSSL::SSL::VERIFY_PEER
    sslcontext.verify_callback = proc do |*args| 
      @logger.debug("Verify peer via FTW::Connection#secure", :callback => settings[:verify_callback])
      if settings[:verify_callback].respond_to?(:call)
        settings[:verify_callback].call(*args)
      end
    end
    sslcontext.ssl_version = :TLSv1
    sslcontext.cert_store = options[:certificate_store]
    @socket = OpenSSL::SSL::SSLSocket.new(@socket, sslcontext)

    # TODO(sissel): Set up local certificat/key stuff. This is required for
    # server-side ssl operation, I think.

    if client?
      do_secure(:connect_nonblock, options[:timeout])
    else
      do_secure(:accept_nonblock, options[:timeout])
    end
  end # def secure

  # Secure this connection.
  #
  # The handshake method for OpenSSL::SSL::SSLSocket is different depending
  # on the mode (client or server).
  #
  # @param [Symbol] handshake_method The method to call on the socket to
  #   complete the ssl handshake. See OpenSSL::SSL::SSLSocket#connect_nonblock
  #   of #accept_nonblock for more details
  def do_secure(handshake_method, timeout=nil)
    # SSLSocket#connect_nonblock will do the SSL/TLS handshake.
    # TODO(sissel): refactor this into a method that both secure and connect
    # methods can call.
    start = Time.now
    begin
      @socket.send(handshake_method)
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
      # So we rescue both IO::Wait{Readable,Writable} and keep trying
      # until timeout occurs.
      #
      
      if !timeout.nil?
        time_left = timeout - (Time.now - start)
        raise SecureHandshakeTimeout.new if time_left < 0
        r, w, e = IO.select([@socket], [@socket], nil, time_left)
      else
        r, w, e = IO.select([@socket], [@socket], nil, timeout)
      end

      # keep going if the socket is ready
      retry if r.size > 0 || w.size > 0
    rescue => e
      @logger.warn(e)
      raise e
    end

    @secure = true
  end # def do_secure

  # Has this connection been secured?
  def secured?
    return @secure
  end # def secured?

  # Is this a client connection?
  def client?
    return @mode == :client
  end # def client?

  # Is this a server connection?
  def server?
    return @mode == :server
  end # def server?

  public(:connect, :connected?, :write, :read, :pushback, :disconnect,
         :writable?, :readable?, :peer, :to_io, :secure, :secured?,
         :client?, :server?)
end # class FTW::Connection

