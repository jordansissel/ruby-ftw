require "net/ftw/namespace"
require "net/ftw/http/request"
require "net/ftw/http/response"
require "openssl"
require "digest/sha1" # TODO(sissel): Maybe just use openssl's one.

# WebSockets, RFC6455.
#
# TODO(sissel): Find a comfortable way to make this websocket stuff 
# both use HTTP::Connection for the HTTP handshake and also be usable
# from HTTP::Client
# TODO(sissel): Also consider SPDY and the kittens.
class Net::FTW::WebSocket
  include Net::FTW::CRLF

  WEBSOCKET_ACCEPT_UUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  # Protocol phases
  # 1. tcp connect
  # 2. http handshake (RFC6455 section 4)
  # 3. websocket protocol

  def initialize(uri)
    uri = Addressable::URI.parse(uri.to_s) if uri.is_a?(URI) || uri.is_a?(String)
    uri.port ||= 80
    @uri = uri

    @connection = Net::FTW::HTTP::Connection.new("#{@uri.host}:#{@uri.port}")
    @key_nonce = generate_key_nonce
    prepare
  end # def initialize

  private
  def prepare
    request = Net::FTW::HTTP::Request.new(@uri)
    response = Net::FTW::HTTP::Response.new

    # RFC6455 section 4.1:
    #  "2.   The method of the request MUST be GET, and the HTTP version MUST
    #        be at least 1.1."
    request.method = "GET"
    request.version = 1.1

    # RFC6455 section 4.2.1 bullet 3
    request.headers.set("Upgrade", "websocket") 
    # RFC6455 section 4.2.1 bullet 4
    request.headers.set("Connection", "Upgrade") 
    # RFC6455 section 4.2.1 bullet 5
    request.headers.set("Sec-WebSocket-Key", @key_nonce)
    # RFC6455 section 4.2.1 bullet 6
    request.headers.set("Sec-WebSocket-Version", 13)
    # RFC6455 section 4.2.1 bullet 7 (optional)
    # The Origin header is optional for non-browser clients.
    #request.headers.set("Origin", ...)
    # RFC6455 section 4.2.1 bullet 8 (optional)
    #request.headers.set("Sec-Websocket-Protocol", ...)
    # RFC6455 section 4.2.1 bullet 9 (optional)
    #request.headers.set("Sec-Websocket-Extensions", ...)
    # RFC6455 section 4.2.1 bullet 10 (optional)
    # TODO(sissel): Any other headers like cookies, auth headers, are allowed.

    # TODO(sissel): This is starting to feel like not the best way to implement
    # protocols.
    @connection.on(@connection.class::CONNECTED) do |address|
      @connection.write(request.to_s)
      @connection.write(CRLF)
    end
    @connection.on(@connection.class::HEADERS_COMPLETE) do |version, status, headers|
      response.status = status
      response.version = version
      headers.each { |field, value| response.headers.add(field, value) }

      # TODO(sissel): Respect redirects

      if websocket_handshake_ok?(request, response)
        p :handshake_valid
      else
        p :handshake_wrong
      end
 
      # Response code must be 101 to switch protocols
      # header 'upgrade' == "websocket"
      # header 'connection' == "Upgrade"
      # header 'sec-websocket-accept' == some auth token based on key
      #   previously given
      #HTTP-1.1 101 Switching Protocols
      #upgrade: websocket
      #connection: Upgrade
      #sec-websocket-accept: ndxQKHQ2QOTvSjlh03NbGWH899g=

      puts response.to_s

      # TODO(sissel): implement the websocket protocol now
      @connection.disconnect
    end # @connection.on HEADERS_COMPLETE

    @connection.run
  end # def prepare

  private
  def generate_key_nonce
    # RFC6455 section 4.1 says:
    # ---
    # 7.   The request MUST include a header field with the name
    #      |Sec-WebSocket-Key|.  The value of this header field MUST be a
    #      nonce consisting of a randomly selected 16-byte value that has
    #      been base64-encoded (see Section 4 of [RFC4648]).  The nonce
    #      MUST be selected randomly for each connection.
    # ---
    #
    # It's not totally clear to me how cryptographically strong this random
    # nonce needs to be, and if it does not need to be strong and it would
    # benefit users who do not have ruby with openssl enabled, maybe just use
    # rand() to generate this string.
    #
    # Thus, generate a random 16 byte string and encode i with base64.
    # Array#pack("m") packs with base64 encoding.
    #return [OpenSSL::Random.random_bytes(16)].pack("m")
    #return ["\0" * 16].pack("m")
    require "base64"
    #a = "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F\x10"
    p : => Base64.encode64(a)
    #AQIDBAUGBwgJCgsMDQ4PEC
    #AQIDBAUGBwgJCgsMDQ4PEA
    return ["\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F\x10"].pack("m")
    #return "dGhlIHNhbXBsZSBub25jZQ=="
  end # def generate_key_nonce

  private
  def websocket_handshake_ok?(request, response)
    # See RFC6455 section 4.2.2
    return false unless response.status == 101 # "Switching Protocols"
    return false unless response.headers.get("upgrade") == "websocket"
    return false unless response.headers.get("connection") == "Upgrade"

    # Now verify Sec-WebSocket-Accept. It should be the SHA-1 of the
    # Sec-WebSocket-Key (in base64) + WEBSOCKET_ACCEPT_UUID
    expected = request.headers.get("Sec-WebSocket-Key") + WEBSOCKET_ACCEPT_UUID
    expected_hash = Digest::SHA1.base64digest(expected)
    p [expected_hash, response.headers.get("Sec-WebSocket-Accept")]
    return false unless response.headers.get("Sec-WebSocket-Accept") == expected_hash

    return true
  end # def websocket_handshake_ok

end # class Net::FTW::WebSocket
