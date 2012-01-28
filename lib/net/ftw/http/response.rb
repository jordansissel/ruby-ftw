require "net/ftw/namespace"
require "net/ftw/http/message"
require "http/parser" # gem http_parser.rb

class Net::FTW::HTTP::Response < Net::FTW::HTTP::Message
  # The HTTP version number
  # See RFC2616 section 6.1: <http://tools.ietf.org/html/rfc2616#section-6.1>
  attr_reader :version

  # The http status code (RFC2616 6.1.1)
  # See RFC2616 section 6.1.1: <http://tools.ietf.org/html/rfc2616#section-6.1.1>
  attr_reader :status

  # The reason phrase (RFC2616 6.1.1)
  # See RFC2616 section 6.1.1: <http://tools.ietf.org/html/rfc2616#section-6.1.1>
  attr_reader :reason

  # Translated from the recommendations listed in RFC2616 section 6.1.1
  # See RFC2616 section 6.1.1: <http://tools.ietf.org/html/rfc2616#section-6.1.1>
  STATUS_REASON_MAP =  {
    100 => "Continue",
    101 => "Switching Protocols",
    200 => "OK",
    201 => "Created",
    202 => "Accepted",
    203 => "Non-Authoritative Information",
    204 => "No Content",
    205 => "Reset Content",
    206 => "Partial Content",
    300 => "Multiple Choices",
    301 => "Moved Permanently",
    302 => "Found",
    303 => "See Other",
    304 => "Not Modified",
    305 => "Use Proxy",
    307 => "Temporary Redirect",
    400 => "Bad Request",
    401 => "Unauthorized",
    402 => "Payment Required",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    406 => "Not Acceptable"
  } # STATUS_REASON_MAP

  public
  def initialize
    super
    @reason = "" # Empty reason string by default. It is not required.
  end # def initialize

  # Set the status code
  public
  def status=(code)
    code = code.to_i if !code.is_a?(Fixnum)
    # TODO(sissel): Validate that 'code' is a 3 digit number
    @status = code

    # Attempt to set the reason if the status code has a known reason
    # recommendation. If one is not found, default to the current reason.
    @reason = STATUS_REASON_MAP.fetch(@status, @reason)
  end # def status=

  # Get the status-line string, like "HTTP/1.0 200 OK"
  public
  def status_line
    # First line is 'Status-Line' from RFC2616 section 6.1
    # Status-Line = HTTP-Version SP Status-Code SP Reason-Phrase CRLF
    # etc...
    return "HTTP-#{version} #{status} #{reason}"
  end # def status_line

  # Define the Message's start_line as status_line
  alias_method :start_line, :status_line

  # TODO(sissel): Methods to write:
  # 1. Parsing a request, use HTTP::Parser from http_parser.rb
  # 2. Building a request from a URI or Addressable::URI
end # class Net::FTW::HTTP::Response

