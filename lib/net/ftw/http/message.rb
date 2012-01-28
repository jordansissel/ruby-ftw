require "net/ftw/namespace"
require "net/ftw/http/headers"

# HTTP Message, RFC2616
class Net::FTW::HTTP::Message
  include Net::FTW::CRLF

  # The HTTP headers. See Net::FTW::HTTP::Headers
  # RFC2616 5.3 - <http://tools.ietf.org/html/rfc2616#section-5.3>
  attr_reader :headers

  # A new HTTP Message. You probably won't use this class much. 
  # See RFC2616 section 4: <http://tools.ietf.org/html/rfc2616#section-4>
  # See Request and Response.
  public
  def initialize
    @headers = Net::FTW::HTTP::Headers.new
    @body = nil
  end # def initialize

  # get a header value
  public
  def [](header)
    return @headers[header]
  end # def []

  public
  def []=(header, value)
    @headers[header] = header
  end # def []=

  # See RFC2616 section 4.3: <http://tools.ietf.org/html/rfc2616#section-4.3>
  public
  def body=(message_body)
    # TODO(sissel): if message_body is a string, set Content-Length header
    # TODO(sissel): if it's an IO object, set Transfer-Encoding to chunked
    # TODO(sissel): if it responds to each or appears to be Enumerable, then
    # set Transfer-Encoding to chunked.
    @body = message_body
  end # def body=

  public
  def body
    # TODO(sissel): verification todos follow...
    # TODO(sissel): RFC2616 section 4.3 - if there is a message body
    # then one of "Transfer-Encoding" *or* "Content-Length" MUST be present.
    # otherwise, if neither header is present, no body is present.
    # TODO(sissel): Responses to HEAD requests or those with status 1xx, 204,
    # or 304 MUST NOT have a body. All other requests have a message body,
    # even if that body is of zero length.
    return @body
  end # def body

  public
  def body?
    return @body.nil?
  end # def body?

  # Serialize this Request according to RFC2616
  # Note: There is *NO* trailing CRLF. This is intentional.
  # The RFC defines:
  #     generic-message = start-line
  #                       *(message-header CRLF)
  #                       CRLF
  #                       [ message-body ]
  # Thus, the CRLF between header and body is not part of the header.
  public
  def to_s
    return [start_line, @headers].join(CRLF)
  end
end # class Net::FTW::HTTP::Message
