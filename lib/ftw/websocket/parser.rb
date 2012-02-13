require "ftw/namespace"
require "ftw/websocket"

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

# XXX: Implement control frames: http://tools.ietf.org/html/rfc6455#section-5.5
class FTW::WebSocket::Parser
  # States are based on the minimal unit of 'byte'
  STATES = [ :flags_and_opcode, :mask_and_payload_init, :payload_length, :payload ]
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

  private
  def transition(state, next_length)
    @logger.debug("Transitioning", :transition => state, :nextlen => next_length)
    @state = state
    need(next_length)
  end # def transition

  public
  def feed(data)
    @buffer << data
    while have?(@need)
      value = send(@state)
      # Return if our state yields a value.
      return value if !value.nil?
      #yield value if !value.nil? and block_given?
    end
  end # def <<

  private
  def have?(length)
    return length <= @buffer.size 
  end # def have?

  private
  def get(length=nil)
    length = @need if length.nil?
    data = @buffer[0 ... length]
    @buffer = @buffer[length .. -1]
    return data
  end # def get

  private
  def need(length)
    @need = length
  end # def need

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

  # http://tools.ietf.org/html/rfc6455#section-5.2
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

  private
  def payload
    data = get(@need)
    transition(:flags_and_opcode, 1)
    return data
  end # def payload
end # class FTW::WebSocket::Parser
