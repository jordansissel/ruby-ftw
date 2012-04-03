require "ftw/namespace"
require "ftw/websocket"
require "ftw/singleton"
require "ftw/websocket/constants"

# This class implements a writer for WebSocket messages over a stream.
#
# Protocol diagram copied from RFC6455
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

class FTW::WebSocket::Writer
  include FTW::WebSocket::Constants
  extend FTW::Singleton

  # A list of valid modes. Used to validate input in #write_text.
  #
  # In :server mode, payloads are not masked. In :client mode, payloads
  # are masked. Masking is described in RFC6455.
  VALID_MODES = [:server, :client]

  private

  # Write the given text in a websocket frame to the connection.
  #
  # Valid 'mode' settings are :server or :client. If :client, the
  # payload will be masked according to RFC6455 section 5.3:
  # http://tools.ietf.org/html/rfc6455#section-5.3
  def write_text(connection, text, mode=:server)
    if !VALID_MODES.include?(mode)
      raise InvalidArgument.new("Invalid message mode: #{mode}, expected one of" \
                                "#{VALID_MODES.inspect}")
    end

    data = []
    pack = []

    # For now, assume single-fragment, text frames
    pack_opcode(data, pack, OPCODE_TEXT)
    pack_payload(data, pack, text, mode)
    connection.write(data.pack(pack.join("")))
  end # def write_text

  # Pack the opcode and flags
  #
  # Currently assumes 'fin' flag is set.
  def pack_opcode(data, pack, opcode)
    # Pack the first byte (fin + opcode)
    data << ((1 << 7) | opcode)
    pack << "C"
  end # def pack_opcode

  # Pack the payload.
  def pack_payload(data, pack, text, mode)
    pack_maskbit_and_length(data, pack, text.length, mode)
    pack_extended_length(data, pack, text.length) if text.length >= 126
    if mode == :client
      mask_key = [rand(1 << 32)].pack("Q")
      pack_mask(data, pack, mask_key)
      data << mask(text, mask_key)
      pack << "A*"
    else
      data << text
      pack << "A*"
    end
  end # def pack_payload

  # Implement masking as described by http://tools.ietf.org/html/rfc6455#section-5.3
  # Basically, we take a 4-byte random string and use it, round robin, to XOR
  # every byte. Like so:
  #   message[0] ^ key[0]
  #   message[1] ^ key[1]
  #   message[2] ^ key[2]
  #   message[3] ^ key[3]
  #   message[4] ^ key[0]
  #   ...
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

  # Pack the first part of the length (mask and 7-bit length)
  def pack_maskbit_and_length(data, pack, length, mode)
    # Pack mask + payload length
    maskbit = (mode == :client) ? (1 << 7) : 0
    if length >= 126
      if length < (1 << 16) # if less than 2^16, use 2 bytes
        lengthbits = 126
      else
        lengthbits = 127
      end
    else
      lengthbits = length
    end
    data << (maskbit | lengthbits)
    pack << "C"
  end # def pack_maskbit_and_length

  # Pack the extended length. 16 bits or 64 bits
  def pack_extended_length(data, pack, length)
    data << length
    if length >= (1 << 16)
      # For lengths >= 16 bits, pack 8 byte length
      pack << "Q>"
    else
      # For lengths < 16 bits, pack 2 byte length
      pack << "S>"
    end
  end # def pack_extended_length

  public(:initialize, :write_text)
end # module FTW::WebSocket::Writer
