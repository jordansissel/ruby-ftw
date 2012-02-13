require "ftw/namespace"
require "openssl"
require "base64" # stdlib 
require "digest/sha1" # stdlib
require "cabin"
require "ftw/websocket/parser"

# WebSockets, RFC6455.
#
# TODO(sissel): Find a comfortable way to make this websocket stuff 
# both use HTTP::Connection for the HTTP handshake and also be usable
# from HTTP::Client
# TODO(sissel): Also consider SPDY and the kittens.
class FTW::WebSocket
  include FTW::CRLF
  include Cabin::Inspectable

  TEXTFRAME = 0x0001

  WEBSOCKET_ACCEPT_UUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  # Protocol phases
  # 1. tcp connect
  # 2. http handshake (RFC6455 section 4)
  # 3. websocket protocol

  # Creates a new websocket and fills in the given http request with any
  # necessary settings.
  public
  def initialize(request)
    @key_nonce = generate_key_nonce
    @request = request
    prepare(@request)
    @parser = FTW::WebSocket::Parser.new
  end # def initialize

  # Set the connection for this websocket. This is usually invoked by FTW::Agent
  # after the websocket upgrade and handshake have been successful.
  #
  # You probably don't call this yourself.
  public
  def connection=(connection)
    @connection = connection
  end # def connection=

  # Prepare the request. This sets any required headers and attributes as
  # specified by RFC6455
  private
  def prepare(request)
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
  end # def prepare

  # Generate a websocket key nonce.
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
    return Base64.strict_encode64(OpenSSL::Random.random_bytes(16))
  end # def generate_key_nonce

  # Is this Response acceptable for our WebSocket Upgrade request?
  public
  def handshake_ok?(response)
    # See RFC6455 section 4.2.2
    return false unless response.status == 101 # "Switching Protocols"
    return false unless response.headers.get("upgrade") == "websocket"
    return false unless response.headers.get("connection") == "Upgrade"

    # Now verify Sec-WebSocket-Accept. It should be the SHA-1 of the
    # Sec-WebSocket-Key (in base64) + WEBSOCKET_ACCEPT_UUID
    expected = @key_nonce + WEBSOCKET_ACCEPT_UUID
    expected_hash = Digest::SHA1.base64digest(expected)
    return false unless response.headers.get("Sec-WebSocket-Accept") == expected_hash

    return true
  end # def handshake_ok?

  # Iterate over each WebSocket message. This method will run forever unless you
  # break from it. 
  #
  # The text payload of each message will be yielded to the block.
  public
  def each(&block)
    loop do
      payload = @parser.feed(@connection.read)
      next if payload.nil?
      yield payload
    end
  end # def each

  # Implement masking as described by http://tools.ietf.org/html/rfc6455#section-5.3
  # Basically, we take a 4-byte random string and use it, round robin, to XOR
  # every byte. Like so:
  #   message[0] ^ key[0]
  #   message[1] ^ key[1]
  #   message[2] ^ key[2]
  #   message[3] ^ key[3]
  #   message[4] ^ key[0]
  #   ...
  private
  def mask(message, key)
    masked = []
    mask_bytes = key.unpack("C4")
    i = 0
    message.each_byte do |byte|
      masked << (byte ^ mask_bytes[i % 4])
      i += 1
    end
    return masked.pack("C*")
  end # def mask

  # Publish a message text.
  #
  # This will send a websocket text frame over the connection.
  public
  def publish(message)
    # TODO(sissel): Support server and client modes.
    # Server MUST NOT mask. Client MUST mask.
    #
    #     0                   1                   2                   3
    #     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    #    +-+-+-+-+-------+-+-------------+-------------------------------+
    #    |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
    #    |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
    #    |N|V|V|V|       |S|             |   (if payload len==126/127)   |
    #    | |1|2|3|       |K|             |                               |
    #    +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
    #    |     Extended payload length continued, if payload len == 127  |
    #    + - - - - - - - - - - - - - - - +-------------------------------+
    #    |                               |Masking-key, if MASK set to 1  |
    #    +-------------------------------+-------------------------------+
    #    | Masking-key (continued)       |          Payload Data         |
    #    +-------------------------------- - - - - - - - - - - - - - - - +
    #    :                     Payload Data continued ...                :
    #    + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
    #    |                     Payload Data continued ...                |
    #    +---------------------------------------------------------------+
    # TODO(sissel): Support 'fin' flag
    # Set 'fin' flag and opcode of 'text frame' 
    length = message.length
    mask_key = [rand(1 << 32)].pack("Q")
    if message.length >= (1 << 16)
      pack = "CCSA4A*" # flags+opcode, mask+len, 2-byte len, payload
      data = [ 0x80 | TEXTFRAME, 0x80 | 126, message.length, mask_key, mask(message, mask_key) ]
      @connection.write(data.pack(pack))
    elsif message.length >= (1 << 7)
      length = 126
      pack = "CCQA4A*" # flags+opcode, mask+len, 8-byte len, payload
      data = [ 0x80 | TEXTFRAME, 0x80 | 127, message.length, mask_key, mask(message, mask_key) ]
      @connection.write(data.pack(pack))
    else
      data = [ 0x80 | TEXTFRAME, 0x80 | message.length, mask_key, mask(message, mask_key) ]
      pack = "CCA4A*" # flags+opcode, mask+len, payload
      @connection.write(data.pack(pack))
    end
  end # def publish
end # class FTW::WebSocket

