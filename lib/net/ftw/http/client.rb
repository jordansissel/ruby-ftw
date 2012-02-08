require "net/ftw/http/connection"
require "net/ftw/http/request"
require "net/ftw/http/response"
require "net/ftw/namespace"
require "socket" # ruby stdlib

# TODO(sissel): Split this out into a general 'client' class (outside http)
# TODO(sissel): EventMachine support

# A client should be like a web browser. It should support lots of active
# connections.
class Net::FTW::HTTP::Client
  include Net::FTW::CRLF

  # Create a new HTTP client. You probably only need one of these.
  def initialize
    @connections = []
  end # def initialize
  
  # TODO(sissel): This method may not stay. I dunno yet.
  public
  def get(uri, headers={})
    # TODO(sissel): enforce uri scheme options? (ws, wss, http, https?)
    prepare("GET", uri, headers)
  end # def get

  public
  def prepare(method, uri, headers={})
    uri = Addressable::URI.parse(uri.to_s) if uri.is_a?(URI)
    uri.port ||= 80

    request = Net::FTW::HTTP::Request.new(uri)
    response = Net::FTW::HTTP::Response.new
    request.method = method
    request.version = 1.1
    headers.each do |key, value|
      request.headers[key] = value
    end

    # TODO(sissel): This is starting to feel like not the best way to implement
    # protocols.
    connection = Net::FTW::HTTP::Connection.new("#{uri.host}:#{uri.port}")
    connection.on(connection.class::CONNECTED) do |address|
      connection.write(request.to_s)
      connection.write(CRLF)
    end
    connection.on(connection.class::HEADERS_COMPLETE) do |version, status, headers|
      response.status = status
      response.version = version
      headers.each { |field, value| response.headers.add(field, value) }

      # TODO(sissel): Split these BODY handlers into separate body-handling
      # classes.
      if response.headers.include?("Content-Length")
        length = response.headers.get("Content-Length").to_i
        connection.on(connection.class::MESSAGE_BODY) do |data|
          length -= data.size
          #$stdout.write data
          if length <= 0
            if response.headers.get("Connection") == "close"
              connection.disconnect
            else
              p :response_complete => response.headers.get("Content-Length")
              # TODO(sissel): This connection is now ready for another HTTP
              # request.
            end

            # TODO(sissel): What to do with the extra bytes?
            if length < 0
              # Length is negative, will be offset on end of data string
              $stderr.puts :TOOMANYBYTES => data[length .. -1]
            end
          end
        end 
      elsif response.headers.get("Transfer-Encoding") == "chunked"
        connection.on(connection.class::MESSAGE_BODY) do |data|
          # TODO(sissel): Handle chunked encoding
          p :chunked => data
        end
      elsif response.version == 1.1
        # No content-length nor transfer-encoding. If this is HTTP/1.1, this is
        # an error, I think. I need to find the specific part of RFC2616 that
        # specifies this.
        connection.disconnect("Invalid HTTP Response received. Response " \
          "version claimed 1.1 but no Content-Length nor Transfer-Encoding "\
          "header was set in the response.")
      end
    end # connection.on HEADERS_COMPLETE
    #connection.run
    return connection
  end # def prepare

  def prepare2(method, uri, headers={})
    uri = Addressable::URI.parse(uri.to_s) if uri.is_a?(URI)
    uri.port ||= 80

    request = Net::FTW::HTTP::Request.new(uri)
    response = Net::FTW::HTTP::Response.new
    request.method = method
    request.version = 1.1
    headers.each do |key, value|
      request.headers[key] = value
    end

    # TODO(sissel): This is starting to feel like not the best way to implement
    # protocols.
    id = "#{uri.scheme}://#{uri.host}:#{uri.port}/..."
    connection = Net::FTW::HTTP::Connection.new("#{uri.host}:#{uri.port}")
    @connections[id] = connection
  end # def prepare2

  # TODO(sissel): 
  def run
    # Select across all active connections, do read_and_trigger, etc.
  end # def run
end # class Net::FTW::HTTP::Client
