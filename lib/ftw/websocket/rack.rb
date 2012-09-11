require "ftw/namespace"
require "ftw/websocket/parser"
require "ftw/crlf"
require "base64" # stdlib 
require "digest/sha1" # stdlib

# A websocket helper for Rack
#
# An example with Sinatra:
#
#     get "/websocket/echo" do
#       ws = FTW::WebSocket::Rack.new(env)
#       stream(:keep_open) do |out|
#         ws.each do |payload|
#           # 'payload' is the text payload of a single websocket message
#           # publish it back to the client
#           ws.publish(payload)
#         end
#       end
#       ws.rack_response
#     end
class FTW::WebSocket::Rack
  include FTW::WebSocket::Constants
  include FTW::CRLF

  private

  # Create a new websocket rack helper... thing.
  #
  # @param rack_env the 'env' bit given to your Rack application
  def initialize(rack_env)
    @env = rack_env
    @handshake_errors = []

    # RFC6455 section 4.2.1 bullet 3
    expect_equal("websocket", @env["HTTP_UPGRADE"],
                 "The 'Upgrade' header must be set to 'websocket'")
    # RFC6455 section 4.2.1 bullet 4
    # Firefox uses a multivalued 'Connection' header, that appears like this:
    #   Connection: keep-alive, Upgrade
    # So we have to split this multivalue field. 
    expect_equal(true,
                 @env["HTTP_CONNECTION"].split(/, +/).include?("Upgrade"),
                 "The 'Connection' header must be set to 'Upgrade'")
    # RFC6455 section 4.2.1 bullet 6
    expect_equal("13", @env["HTTP_SEC_WEBSOCKET_VERSION"],
                 "Sec-WebSocket-Version must be set to 13")

    # RFC6455 section 4.2.1 bullet 5
    @key = @env["HTTP_SEC_WEBSOCKET_KEY"] 

    @parser = FTW::WebSocket::Parser.new
  end # def initialize

  # Test values for equality. This is used in handshake tests.
  def expect_equal(expected, actual, message)
    if expected != actual
      @handshake_errors << message
    end
  end # def expected

  # Is this a valid handshake?
  def valid?
    return @handshake_errors.empty?
  end # def valid?

  # Get the response Rack is expecting.
  #
  # If this was a valid websocket request, it will return a response
  # that completes the HTTP portion of the websocket handshake.
  #
  # If this was an invalid websocket request, it will return a
  # 400 status code and descriptions of what failed in the body
  # of the response.
  #
  # @return [number, hash, body]
  def rack_response
    if valid?
      # Return the status, headers, body that is expected.
      sec_accept = @key + WEBSOCKET_ACCEPT_UUID
      sec_accept_hash = Digest::SHA1.base64digest(sec_accept)

      headers = {
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Accept" => sec_accept_hash
      }
      # See RFC6455 section 4.2.2
      return 101, headers, nil
    else
      # Invalid request, tell the client why.
      return 400, { "Content-Type" => "text/plain" },
        @handshake_errors.map { |m| "#{m}#{CRLF}" }
    end
  end # def rack_response

  # Enumerate each websocket payload (message).
  #
  # The payload of each message will be yielded to the block.
  #
  # Example:
  #
  #     ws.each do |payload|
  #       puts "Received: #{payload}"
  #     end
  def each
    connection = @env["ftw.connection"]
    # There seems to be a bug in http_parser.rb where websocket responses
    # lead with a newline for some reason.  It's like the header terminator
    # CRLF still has the LF character left in the buffer. Work around it.
    data = connection.read
    if data[0] == "\n"
      connection.pushback(data[1..-1])
    else
      connection.pushback(data)
    end

    while true
      begin
        data = connection.read(16384)
      rescue EOFError
        # connection shutdown, close up.
        break
      end

      @parser.feed(data) do |payload|
        yield payload if !payload.nil?
      end
    end
  end # def each

  # Publish a message over this websocket.
  #
  # @param message Publish a string message to the websocket.
  def publish(message)
    writer = FTW::WebSocket::Writer.singleton
    writer.write_text(@env["ftw.connection"], message)
  end # def publish

  public(:initialize, :valid?, :rack_response, :each, :publish)
end # class FTW::WebSocket::Rack
