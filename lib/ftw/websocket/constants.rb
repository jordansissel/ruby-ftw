
# The UUID comes from: 
# http://tools.ietf.org/html/rfc6455#page-23
#
# The opcode definitions come from:
# http://tools.ietf.org/html/rfc6455#section-11.8
module FTW::WebSocket::Constants
  # websocket uuid, used in hash signing of websocket responses (RFC6455)
  WEBSOCKET_ACCEPT_UUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  # Indication that this frame is a continuation in a fragmented message
  # See RFC6455 page 33.
  OPCODE_CONTINUATION = 0

  # Indication that this frame contains a text message
  OPCODE_TEXT = 1

  # Indication that this frame contains a binary message
  OPCODE_BINARY = 2

  # Indication that this frame is a 'connection close' message
  OPCODE_CLOSE = 8

  # Indication that this frame is a 'ping' message
  OPCODE_PING = 9

  # Indication that this frame is a 'pong' message
  OPCODE_PONG = 10
end # module FTW::WebSocket::Constants
