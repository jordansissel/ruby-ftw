require "ftw/namespace"
require "ftw/http/message"
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
    return "HTTP-#{version} #{status} #{reason}"
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
      if headers.include?("Content-Length")
        read_body_length(headers["Content-Length"].to_i, &block)
      elsif headers["Transfer-Encoding"] == "chunked"
        read_body_chunked(&block)
      end
    else
      yield @body
    end
  end # def read_body

  public
  def read_body_length(length, &block)
    while length > 0
      data = @body.read
      length -= data.size
      yield data[0 ... length]
      @body.pushback(data[length .. -1]) if length < 0
    end
  end # def read_body_length

  # This is kind of messed, need to fix it.
  public
  def read_body_chunked(&block)
    # RFC2616 section 3.6.1 <http://tools.ietf.org/html/rfc2616#section-3.6.1>
    # Chunked-Body   = *chunk
    #                  last-chunk
    #                  trailer
    #                  CRLF
    # chunk          = chunk-size [ chunk-extension ] CRLF
    #                  chunk-data CRLF
    # chunk-size     = 1*HEX
    # last-chunk     = 1*("0") [ chunk-extension ] CRLF
    # chunk-extension= *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
    # chunk-ext-name = token
    # chunk-ext-val  = token | quoted-string
    # chunk-data     = chunk-size(OCTET)
    # trailer        = *(entity-header CRLF)
    last_chunk_seen = false
    state = :chunksize
    chunksize = 0
    while true # will break on special conditions below
      data = @body.read
      p :state => state, :data => data[0..20] + "..." + data[-20..-1]
      case state
        when :chunksize # Reading the chunk-size
          chunksize_str = data[/^[A-Fa-f0-9]+\r\n/]
          if chunksize_str
            #p :chunksize => chunksize
            chunksize = chunksize_str.to_i(16)
            state = :chunkdata
            @body.pushback(data[chunksize_str.length .. -1])
          end
        when :chunkdata # Reading the chunk data
          if data.size < chunksize
            @body.pushback(data)
            next
          end
          chunk = data[0...chunksize]
          # push back the remainder if any
          @body.pushback(data[chunksize..-1]) if data.size > chunksize
          yield chunk
          state = :crlf
        when :crlf
          if data.size < 2
            @body.pushback(data)
            next
          end
          raise "Expected CRLF (#{CRLF.inspect}), got #{data[0...2].inspect}" if data[0...2] != CRLF
          @body.pushback(data[2..-1]) if data.size > 2
          if chunksize == 0
            state = :trailer 
          else
            state = :chunksize
          end
          # Reset read size
          chunksize = 16384
        when :trailer
          p :trailer
          # TODO(sissel): Parse trailer, just entity headers
      end
    end
  end # def read_body_chunked

  # TODO(sissel): Methods to write:
  # 1. Parsing a request, use HTTP::Parser from http_parser.rb
  # 2. Building a request from a URI or Addressable::URI
end # class FTW::Response

