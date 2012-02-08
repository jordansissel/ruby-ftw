require "net/ftw/connection2"
require "net/ftw/http/request"
require "net/ftw/http/response"
require "net/ftw/namespace"
require "socket" # ruby stdlib

# TODO(sissel): Split this out into a general 'client' class (outside http)
# TODO(sissel): EventMachine support

# A client should be like a web browser. It should support lots of active
# connections.
class Net::FTW::HTTP::Client2
  include Net::FTW::CRLF

  # Create a new HTTP client. You probably only need one of these.
  def initialize
    @connections = []
  end # def initialize
  
  # TODO(sissel): This method may not stay. I dunno yet.
  public
  def get(uri, headers={})
    # TODO(sissel): enforce uri scheme options? (ws, wss, http, https?)
    return prepare("GET", uri, headers)
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

    connection = Net::FTW::Connection2.new("#{uri.host}:#{uri.port}")
    return fiberup(connection, request, response)
  end # def prepare

  def fiberup(connection, request, response)
    # Body just passes through
    body = Fiber.new do |data|
      Fiber.yield data
    end

    # Parse the HTTP headers
    headers = Fiber.new do |data|
      parser = HTTP::Parser.new
      headers_done = false
      parser.on_headers_complete = proc { headers_done = true; :stop }
      while true do
        offset = parser << data
        if headers_done
          version = "#{parser.http_major}.#{parser.http_minor}".to_f
          p :processing
          Fiber.yield [version, parser.status_code, parser.headers]
          p :processing
          # Transfer control to the 'body' fiber.
          body.transfer(data[offset..-1])
        end
        p :waiting
        data = Fiber.resume
      end
    end

    connect = Fiber.new do
      connection.connect
      connection.write(request.to_s + CRLF)
      while true do
        data = connection.read(16384)
        headers.resume data
      end
    end
    return connect
  end # def fiberup
end # class Net::FTW::HTTP::Client2
