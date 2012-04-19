require "ftw/namespace"
require "ftw/protocol"
require "ftw/http/message"
require "cabin" # gem cabin
require "http/parser" # gem http_parser.rb

# An HTTP Response.
#
# See RFC2616 section 6: <http://tools.ietf.org/html/rfc2616#section-6>
class FTW::Response 
  include FTW::HTTP::Message
  include FTW::Protocol

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

  private

  # Create a new Response.
  def initialize
    super
    @logger = Cabin::Channel.get
    @reason = "" # Empty reason string by default. It is not required.
  end # def initialize

  # Is this response a redirect?
  def redirect?
    # redirects are 3xx
    return @status >= 300 && @status < 400
  end # redirect?

  # Is this response an error?
  def error?
    # 4xx and 5xx are errors
    return @status >= 400 && @status < 600
  end # def error?

  # Set the status code
  def status=(code)
    code = code.to_i if !code.is_a?(Fixnum)
    # TODO(sissel): Validate that 'code' is a 3 digit number
    @status = code

    # Attempt to set the reason if the status code has a known reason
    # recommendation. If one is not found, default to the current reason.
    @reason = STATUS_REASON_MAP.fetch(@status, @reason)
  end # def status=

  # Get the status-line string, like "HTTP/1.0 200 OK"
  def status_line
    # First line is 'Status-Line' from RFC2616 section 6.1
    # Status-Line = HTTP-Version SP Status-Code SP Reason-Phrase CRLF
    # etc...
    return "HTTP/#{version} #{status} #{reason}"
  end # def status_line

  # Define the Message's start_line as status_line
  alias_method :start_line, :status_line

  # Is this Response the result of a successful Upgrade request?
  def upgrade?
    return false unless status == 101 # "Switching Protocols"
    return false unless headers["Connection"] == "Upgrade"
    return true
  end # def upgrade?

  public(:status=, :status, :reason, :initialize, :upgrade?, :redirect?,
         :error?, :status_line)
end # class FTW::Response

