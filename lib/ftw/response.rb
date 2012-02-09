require "ftw/namespace"
require "ftw/http/message"
require "cabin" # gem cabin
require "http/parser" # gem http_parser.rb

class FTW::Response 
  include FTW::HTTP::Message

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

  attr_accessor :body

  public
  def initialize
    super
    @logger = Cabin::Channel.get
    @reason = "" # Empty reason string by default. It is not required.
  end # def initialize

  # Is this response a redirect?
  public
  def redirect?
    # redirects are 3xx
    return @status >= 300 && @status < 400
  end # redirect?

  # Is this response an error?
  public
  def error?
    # 4xx and 5xx are errors
    return @status >= 400 && @status < 600
  end # def error?

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
    return "HTTP/#{version} #{status} #{reason}"
  end # def status_line

  # Define the Message's start_line as status_line
  alias_method :start_line, :status_line

  public
  def body=(connection_or_string)
    @body = connection_or_string
  end # def body=

  public
  def read_body(&block)
    if @body.respond_to?(:read)
      if headers.include?("Content-Length") and headers["Content-Length"].to_i > 0
        @logger.debug("Reading body with Content-Length")
        read_body_length(headers["Content-Length"].to_i, &block)
      elsif headers["Transfer-Encoding"] == "chunked"
        @logger.debug("Reading body with chunked encoding")
        read_body_chunked(&block)
      end

      # If this is a poolable resource, release it (like a FTW::Connection)
      @body.release if @body.respond_to?(:release)
    elsif !@body.nil?
      yield @body
    end
  end # def read_body

  # Read the length bytes from the body. Yield each chunk read to the block
  # given.
  public
  def read_body_length(length, &block)
    remaining = length
    while remaining > 0
      data = @body.read
      @logger.debug("Read bytes", :length => data.size)
      if data.size > remaining
        # Read too much data, only wanted part of this. Push the rest back.
        yield data[0..remaining]
        remaining = 0
        @body.pushback(data[remaining .. -1]) if remaining < 0
      else
        yield data
        remaining -= data.size
      end
    end
  end # def read_body_length

  # This is kind of messed, need to fix it.
  public
  def read_body_chunked(&block)
    parser = HTTP::Parser.new

    # Fake fill-in the response we've already read into the parser.
    parser << to_s
    parser << CRLF
    parser.on_body = block
    done = false
    parser.on_message_complete = proc { done = true }

    while !done # will break on special conditions below
      data = @body.read
      offset = parser << data
      if offset != data.length
        raise "Parser dis not consume all data read?"
      end
    end
  end # def read_body_chunked

  public
  def upgrade?
    return false unless status == 101 # "Switching Protocols"
    return false unless headers["Connection"] == "Upgrade"
    #return false unless headers["Upgrade"] == "websocket"
    return true
  end # def upgrade

  # TODO(sissel): Methods to write:
  # 1. Parsing a request, use HTTP::Parser from http_parser.rb
  # 2. Building a request from a URI or Addressable::URI
end # class FTW::Response

