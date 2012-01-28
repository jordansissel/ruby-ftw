require "net/ftw/namespace"
require "net/ftw/http/message"
require "addressable/uri" # gem addressable
require "uri" # ruby stdlib
require "http/parser" # gem http_parser.rb

# An HTTP Request.
#
# See RFC2616 section 5: <http://tools.ietf.org/html/rfc2616#section-5>
class Net::FTW::HTTP::Request < Net::FTW::HTTP::Message
  include Net::FTW::CRLF

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

  # Lemmings. Everyone else calls Request-URI the 'path' - so I should too.
  alias_method :path, :request_uri

  # The HTTP version. See VALID_VERSIONS for valid versions.
  # This will always be a Numeric object.
  attr_accessor :version

  VALID_VERSIONS = [1.0, 1.1]

  public
  def initialize(uri=nil)
    super()
    use_uri(uri) if !uri.nil?
    @version = 1.1
  end # def initialize

  public
  def use_uri(uri)
    # Convert URI objects to Addressable::URI
    uri = Addressable::URI.parse(uri.to_s) if uri.is_a?(URI)

    # TODO(sissel): Use normalized versions of these fields?
    # uri.host
    # uri.port
    # uri.scheme
    # uri.path
    # uri.password
    # uri.user
    @request_uri = uri.path
    @headers.set("Host", uri.host)
    
    # TODO(sissel): support authentication
  end # def use_uri

  # Set the HTTP version. Must be a valid version. See VALID_VERSIONS.
  public
  def version=(ver)
    # Accept string "1.0" or simply "1", etc.
    ver = ver.to_f if !ver.is_a?(Float)

    if !VALID_VERSIONS.include?(ver)
      raise ArgumentError.new("#{self.class.name}#version = #{ver.inspect} is" \
        "invalid. It must be a number, one of #{VALID_VERSIONS.join(", ")}")
    end
    @version = ver
  end # def version=

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

  # TODO(sissel): Methods to write:
  # 1. Parsing a request, use HTTP::Parser from http_parser.rb
  # 2. Building a request from a URI or Addressable::URI
end # class Net::FTW::HTTP::Request < Message
