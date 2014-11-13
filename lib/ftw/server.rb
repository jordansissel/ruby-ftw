require "ftw/namespace"

# A web server.
class FTW::Server
  # This class is raised when an error occurs starting the server sockets.
  class ServerSetupFailure < StandardError; end

  # This class is raised when an invalid address is given to the server to
  # listen on.
  class InvalidAddress < StandardError; end

  private

  # The pattern addresses must match. This is used in FTW::Server#initialize.
  ADDRESS_RE = /^(.*):([^:]+)$/

  # Create a new server listening on the given addresses
  #
  # This method will create, bind, and listen, so any errors during that
  # process be raised as ServerSetupFailure
  #
  # The parameter 'addresses' can be a single string or an array of strings.
  # These strings MUST have the form "address:port". If the 'address' part
  # is missing, it is assumed to be 0.0.0.0
  def initialize(addresses)
    addresses = [addresses] if !addresses.is_a?(Array)
    dns = FTW::DNS.singleton

    @control_lock = Mutex.new
    @sockets = {}

    failures = []
    # address format is assumed to be 'host:port'
    # TODO(sissel): The split on ":" breaks ipv6 addresses, yo.
    addresses.each do |address|
      m = ADDRESS_RE.match(address)
      if !m
        raise InvalidAddress.new("Invalid address #{address.inspect}, spected string with format 'host:port'")
      end
      host, port = m[1..2] # first capture is host, second capture is port

      # Permit address being simply ':PORT'
      host = "0.0.0.0" if host.nil?

      # resolve each hostname, use the first one that successfully binds.
      local_failures = []
      dns.resolve(host).each do |ip|
        #family = ip.include?(":") ? Socket::AF_INET6 : Socket::AF_INET
        #socket = Socket.new(family, Socket::SOCK_STREAM, 0)
        #sockaddr = Socket.pack_sockaddr_in(port, ip)
        socket = TCPServer.new(ip, port)
        #begin
          #socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
          #socket.bind(sockaddr)
          # If we get here, bind was successful
        #rescue Errno::EADDRNOTAVAIL => e
          # TODO(sissel): Record this failure.
          #local_failures << "Could not bind to #{ip}:#{port}, address not available on this system."
          #next
        #rescue Errno::EACCES
          # TODO(sissel): Record this failure.
          #local_failures << "No permission to bind to #{ip}:#{port}: #{e.inspect}"
          #next
        #end

        begin
          socket.listen(100)
        rescue Errno::EADDRINUSE
          local_failures << "Address in use, #{ip}:#{port}, cannot listen."
          next
        end

        # Break when successfully listened
        #p :accept? => socket.respond_to?(:accept)
        @sockets["#{host}(#{ip}):#{port}"] = socket
        local_failures.clear
        break
      end
      failures += local_failures
    end

    # This allows us to interrupt the #each_connection's select() later
    # when anyone calls stop()
    @stopper = IO.pipe

    # Abort if there were failures
    raise ServerSetupFailure.new(failures) if failures.any?
  end # def initialize

  # Stop serving.
  def stop
    @stopper[1].syswrite(".")
    @stopper[1].close()
    @control_lock.synchronize do
      @sockets.each do |name, socket|
        socket.close
      end
      @sockets.clear
    end
  end # def stop

  # Yield FTW::Connection instances to the block as clients connect.
  def each_connection(&block)
    # TODO(sissel): Select on all sockets
    # TODO(sissel): Accept and yield to the block
    stopper = @stopper[0]
    while true
      @control_lock.synchronize do
        sockets = @sockets.values + [stopper]
        read, write, error = IO.select(sockets, nil, nil, nil)
        break if read.include?(stopper)
        read.each do |serversocket|
          socket, addrinfo = serversocket.accept
          connection = FTW::Connection.from_io(socket)
          yield connection
        end
      end
    end
  end # def each_connection

  public(:initialize, :stop, :each_connection)
end # class FTW::Server

