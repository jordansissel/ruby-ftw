require "ftw/namespace"
require "ftw/http/headers"
require "ftw/crlf"

# HTTP Message, RFC2616
# For specification, see RFC2616 section 4: <http://tools.ietf.org/html/rfc2616#section-4>
#
# You probably won't use this class much. Instead, check out {FTW::Request} and {FTW::Response}
module FTW::HTTP::Message
  include FTW::CRLF

  # The HTTP headers - See {FTW::HTTP::Headers}.
  # RFC2616 5.3 - <http://tools.ietf.org/html/rfc2616#section-5.3>
  attr_reader :headers

  # The HTTP version. See {VALID_VERSIONS} for valid versions.
  # This will always be a Numeric object.
  # Both Request and Responses have version, so put it in the parent class.
  attr_accessor :version

  # HTTP Versions that are valid.
  VALID_VERSIONS = [1.0, 1.1]

  private

  # A new HTTP message.
  def initialize
    @headers = FTW::HTTP::Headers.new
    @body = nil
  end # def initialize

  # Get a header value by field name.
  #
  # @param [String] the name of the field. (case insensitive)
  def [](field)
    return @headers[field]
  end # def []

  # Set a header field
  #
  # @param [String] the name of the field. (case insensitive)
  # @param [String] the value to set for this field
  def []=(field, value)
    @headers[field] = value
  end # def []=

  # Set the body of this message
  #
  # The 'message_body' can be an IO-like object, Enumerable, or String.
  #
  # See RFC2616 section 4.3: <http://tools.ietf.org/html/rfc2616#section-4.3>
  def body=(message_body)
    # TODO(sissel): if message_body is a string, set Content-Length header
    # TODO(sissel): if it's an IO object, set Transfer-Encoding to chunked
    # TODO(sissel): if it responds to each or appears to be Enumerable, then
    # set Transfer-Encoding to chunked.
    @body = message_body

    # don't set any additional length/encoding headers if they are already set.
    return if headers.include?("Content-Length") or headers.include?("Transfer-Encoding")

    if (message_body.respond_to?(:read) or message_body.respond_to?(:each)) and
      headers["Transfer-Encoding"] = "chunked"
    else
      headers["Content-Length"] = message_body.bytesize
    end
  end # def body=

  # Get the body of this message
  #
  # Returns an Enumerable, IO-like object, or String, depending on how this
  # message was built.
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

  # Should this message have a content?
  #
  # In HTTP 1.1, there is a body if response sets Content-Length *or*
  # Transfer-Encoding, it has a body. Otherwise, there is no body.
  def content?
    return (headers.include?("Content-Length") and headers["Content-Length"].to_i > 0) \
      || headers.include?("Transfer-Encoding")
  end # def content?

  # Does this message have a body?
  def body?
    return !@body.nil?
  end # def body?

  # Set the HTTP version. Must be a valid version. See VALID_VERSIONS.
  def version=(ver)
    # Accept string "1.0" or simply "1", etc.
    ver = ver.to_f if !ver.is_a?(Float)

    if !VALID_VERSIONS.include?(ver)
      raise ArgumentError.new("#{self.class.name}#version = #{ver.inspect} is" \
        "invalid. It must be a number, one of #{VALID_VERSIONS.join(", ")}")
    end
    @version = ver
  end # def version=

  # Serialize this Request according to RFC2616
  # Note: There is *NO* trailing CRLF. This is intentional.
  # The RFC defines:
  #     generic-message = start-line
  #                       *(message-header CRLF)
  #                       CRLF
  #                       [ message-body ]
  # Thus, the CRLF between header and body is not part of the header.
  def to_s
    return [start_line, @headers].join(CRLF)
  end

  public(:initialize, :headers, :version, :version=, :[], :[]=, :body=, :body,
         :content?, :body?, :to_s)
end # class FTW::HTTP::Message
