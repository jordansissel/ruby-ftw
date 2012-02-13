require "ftw/namespace"
require "ftw/websocket"

# This class implements a parser for WebSocket messages over a stream.
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
class FTW::WebSocket::Parser
  # XXX: Implement control frames: http://tools.ietf.org/html/rfc6455#section-5.5

  # States are based on the minimal unit of 'byte'
  STATES = [ :flags_and_opcode, :mask_and_payload_init, :payload_length, :payload ]

  # A new WebSocket protocol parser.
  def initialize
    @logger = Cabin::Channel.get($0)
    @opcode = 0
    @masking_key = ""
    @flag_final_payload = 0
    @flag_mask = 0

    transition(:flags_and_opcode, 1)
    @buffer = ""
    @buffer.force_encoding("BINARY")
  end # def initialize

  # Transition to a specified state and set the next required read length.
  private
  def transition(state, next_length)
    @logger.debug("Transitioning", :transition => state, :nextlen => next_length)
    @state = state
    need(next_length)
  end # def transition

  # Feed data to this parser.
  # 
  # Currently, it will return the raw payload of websocket messages.
  # Otherwise, it returns nil if no complete message has yet been consumed.
  public
  def feed(data)
    @buffer << data
    while have?(@need)
      value = send(@state)
      # Return if our state yields a value.
      return value if !value.nil?
      #yield value if !value.nil? and block_given?
    end
    return nil
  end # def <<

  # Do we have at least 'length' bytes in the buffer?
  private
  def have?(length)
    return length <= @buffer.size 
  end # def have?

  # Get 'length' string from the buffer.
  private
  def get(length=nil)
    length = @need if length.nil?
    data = @buffer[0 ... length]
    @buffer = @buffer[length .. -1]
    return data
  end # def get

  # Set the minimum number of bytes we need in the buffer for the next read.
  private
  def need(length)
    @need = length
  end # def need

  # State: Flags (fin, etc) and Opcode. 
  # See: http://tools.ietf.org/html/rfc6455#section-5.3
  private
  def flags_and_opcode
    #     0              
    #     0 1 2 3 4 5 6 7
    #    +-+-+-+-+-------
    #    |F|R|R|R| opcode
    #    |I|S|S|S|  (4)  
    #    |N|V|V|V|       
    #    | |1|2|3|       
    byte = get.bytes.first
    @opcode = byte & 0xF # last 4 bites
    @fin = (byte & 0x80 == 0x80)# first bit

    #p :byte => byte, :bits => byte.to_s(2), :opcode => @opcode, :fin => @fin
    # mask_and_payload_length has a minimum length
    # of 1 byte, so start there.
    transition(:mask_and_payload_init, 1)

    # This state yields no output.
    return nil
  end # def flags_and_opcode

  # State: mask_and_payload_init
  # See: http://tools.ietf.org/html/rfc6455#section-5.2
  private
  def mask_and_payload_init
    byte = get.bytes.first
    @mask = byte & 0x80 # first bit (msb)
    @payload_length = byte & 0x7F # remaining bits are the length
    case @payload_length
      when 126 # 2 byte, unsigned value is the payload length
        transition(:extended_payload_length, 2)
      when 127 # 8 byte, unsigned value is the payload length
        transition(:extended_payload_length, 8)
      else
        # Keep the current payload length, a 7 bit value.
        # Go to read the payload
        transition(:payload, @payload_length)
    end # case @payload_length

    # This state yields no output.
    return nil
  end # def mask_and_payload_init

  # State: payload_length
  # This is the 'extended payload length' with support for both 16 
  # and 64 bit lengths.
  # See: http://tools.ietf.org/html/rfc6455#section-5.2
  private
  def payload_length
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
    data = get
    case @need
      when 2
        @payload_length = data.unpack("S")
      when 8
        @payload_length = data.unpack("Q")
      else
        raise "Unknown payload_length byte length '#{@need}'"
    end

    transition(:payload, @payload_length)

    # This state yields no output.
    return nil
  end # def payload_length

  # State: payload
  # Read the full payload and return it.
  # See: http://tools.ietf.org/html/rfc6455#section-5.3
  #
  private
  def payload
    # TODO(sissel): Handle massive payload lengths without exceeding memory.
    # Perhaps if the payload is large (say, larger than 500KB by default),
    # instead of returning the whole thing, simply return an Enumerable that
    # yields chunks of the payload. There's no reason to buffer the entire
    # thing. Have the consumer of this library make that decision.
    data = get(@need)
    transition(:flags_and_opcode, 1)
    return data
  end # def payload
end # class FTW::WebSocket::Parser
