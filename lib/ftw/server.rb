require "ftw/namespace"

# A web server.
class FTW::Server
  # This class is raised when an error occurs starting the server sockets.
  class BindFailure < StandardError; end

  private

  # Create a new server listening on the given addresses
  #
  # This will raise BindFailure
  def initialize(addresses)
    addresses = [addresses] if !addresses.is_a?(Array)
    dns = FTW::DNS.singleton

    @sockets = {}

    failures = []
    addresses.collect { |a| a.split(":", 2) }.each do |host, port|
      dns.resolve(host).each do |ip|
        family = ip.include?(":") ? Socket::AF_INET6 : Socket::AF_INET
        socket = Socket.new(family, Socket::SOCK_STREAM, 0)
        sockaddr = Socket.pack_sockaddr_in(port, ip)
        begin
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
          socket.bind(sockaddr)
          # If we get here, bind was successful
        rescue Errno::EADDRNOTAVAIL => e
          # TODO(sissel): Record this failure.
          failures << "Could not bind to #{ip}:#{port}, address not available on this system."
          next
        rescue Errno::EACCES
          # TODO(sissel): Record this failure.
          failures << "No permission to bind to #{ip}:#{port}: #{e.inspect}"
          next
        end

        begin
          socket.listen(100)
        rescue Errno::EADDRINUSE
          failures << "Address in use, #{ip}:#{port}, cannot listen."
          next
        end

        # Break when successfully listened
        @sockets["#{host}(#{ip}):#{port}"] = socket
        break
      end
    end

    # Abort if there were failures
    raise ServerSetupFailure.new(failures) if failures.any?
  end # def initialize

  # Close the server sockets
  def close
    @sockets.each do |name, socket|
      socket.close
    end
  end # def close

  # Yield FTW::Connection instances to the block as clients connect.
  def each_connection(&block)
    # TODO(sissel): Select on all sockets
    # TODO(sissel): Accept and yield to the block
    while true
      sockets = @sockets.values
      read, write, error = IO.select(sockets, nil, nil, nil)
      read.each do |serversocket|
        socket, addrinfo = serversocket.accept
        connection = FTW::Connection.from_io(socket)
        yield connection
      end
    end
  end # def each_connection

  public(:initialize, :close, :each_connection)
end # class FTW::Server

