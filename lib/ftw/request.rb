require "ftw/namespace"
require "ftw/http/message"
require "ftw/response"
require "addressable/uri" # gem addressable
require "uri" # ruby stdlib
require "http/parser" # gem http_parser.rb
require "ftw/crlf"

# An HTTP Request.
#
# See RFC2616 section 5: <http://tools.ietf.org/html/rfc2616#section-5>
class FTW::Request
  include FTW::HTTP::Message
  include FTW::CRLF

  # The http method. Like GET, PUT, POST, etc..
  # RFC2616 5.1.1 - <http://tools.ietf.org/html/rfc2616#section-5.1.1>
  #
  # Warning: this accessor obscures the ruby Kernel#method() method.
  # I would like to call this 'verb', but my preference is first to adhere to
  # RFC terminology. Further, ruby's stdlib Net::HTTP calls this 'method' as
  # well (See Net::HTTPGenericRequest).
  attr_accessor :method

  # This is the Request-URI. Many people call this the 'path' of the request.
  # RFC2616 5.1.2 - <http://tools.ietf.org/html/rfc2616#section-5.1.2>
  attr_accessor :request_uri

  # Lemmings. Everyone else calls Request-URI the 'path' (including me, most of
  # the time), so let's just follow along.
  alias_method :path, :request_uri

  # RFC2616 section 14.23 allows the Host header to include a port, but I have
  # never seen this in practice, and I shudder to think about what poorly-behaving
  # web servers will barf if the Host header includes a port. So, instead of
  # storing the port in the Host header, it is stored here. It is not included
  # in the Request when sent from a client and it is not used on a server.
  attr_accessor :port

  public
  def initialize(uri=nil)
    super()
    use_uri(uri) if !uri.nil?
    @version = 1.1
    @port = 80
  end # def initialize

  # Set the connection to use for this request.
  public
  def connection=(connection)
    @connection = connection
  end # def connection=

  # EXTERMINATE .. err.. execute this request on a connection.
  #
  # Writes the request, returns a Response object.
  public
  def execute(connection)
    connection.write(to_s + CRLF)

    # TODO(sissel): Support request a body.

    parser = HTTP::Parser.new
    headers_done = false
    parser.on_headers_complete = proc { headers_done = true; :stop }

    while true
      data = connection.read
      #p [data[0..40], data[-20..-1]].join("...")
      #p data
      offset = parser << data
      # headers_done will be set to true when parser finishes parsing the http
      # headers for this request
      next if !headers_done

      # Done reading response header
      response = FTW::Response.new
      response.version = "#{parser.http_major}.#{parser.http_minor}".to_f
      response.status = parser.status_code
      parser.headers.each { |field, value| response.headers.add(field, value) }

      # If we consumed part of the body while parsing headers, put it back
      # onto the connection's read buffer so the next consumer can use it.
      if offset < data.length
        connection.pushback(data[offset .. -1])
      end
      return response
    end
  end # def execute

  # TODO(sissel): Methods to write:
  # 1. Parsing a request, use HTTP::Parser from http_parser.rb
  # 2. Building a request from a URI or Addressable::URI

  public
  def use_uri(uri)
    # Convert URI objects to Addressable::URI
    case uri
      when URI, String
        uri = Addressable::URI.parse(uri.to_s)
    end

    # TODO(sissel): Use normalized versions of these fields?
    # uri.host
    # uri.port
    # uri.scheme
    # uri.path
    # uri.password
    # uri.user
    @request_uri = uri.path
    @headers.set("Host", uri.host)
    if uri.port.nil?
      # default to port 80
      uri.port = { "http" => 80, "https" => 443 }.fetch(uri.scheme, 80)
    end
    @port = uri.port
    
    # TODO(sissel): support authentication
  end # def use_uri

  # Set the method for this request. Usually something like "GET" or "PUT"
  # etc. See <http://tools.ietf.org/html/rfc2616#section-5.1.1>
  public
  def method=(method)
    # RFC2616 5.1.1 doesn't say the method has to be uppercase.
    # It can be any 'token' besides the ones defined in section 5.1.1:
    # The grammar for 'token' is:
    #          token          = 1*<any CHAR except CTLs or separators>
    # TODO(sissel): support section 5.1.1 properly. Don't upcase, but 
    # maybe upcase things that are defined in 5.1.1 like GET, etc.
    @method = method.upcase
  end # def method=

  # Get the request line (first line of the http request)
  # From the RFC: Request-Line   = Method SP Request-URI SP HTTP-Version CRLF
  #
  # Note: I skip the trailing CRLF. See the to_s method where it is provided.
  def request_line
    return "#{method} #{request_uri} HTTP/#{version}"
  end # def request_line

  # Define the Message's start_line as request_line
  alias_method :start_line, :request_line
end # class FTW::Request < Message
