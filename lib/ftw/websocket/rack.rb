require "ftw/namespace"
require "ftw/websocket/parser"
require "base64" # stdlib 
require "digest/sha1" # stdlib

class FTW::WebSocket::Rack
  WEBSOCKET_ACCEPT_UUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  private

  def initialize(rack_env)
    @env = rack_env
    @handshake_errors = []

    # RFC6455 section 4.2.1 bullet 3
    expect_equal("websocket", @env["HTTP_UPGRADE"],
                 "The 'Upgrade' header must be set to 'websocket'")
    # RFC6455 section 4.2.1 bullet 4
    expect_equal("Upgrade", @env["HTTP_CONNECTION"],
                 "The 'Connection' header must be set to 'Upgrade'")
    # RFC6455 section 4.2.1 bullet 6
    expect_equal("13", @env["HTTP_SEC_WEBSOCKET_VERSION"],
                 "Sec-WebSocket-Version must be set to 13")

    # RFC6455 section 4.2.1 bullet 5
    @key = @env["HTTP_SEC_WEBSOCKET_KEY"] 

    @parser = FTW::WebSocket::Parser.new
  end # def initialize

  def expect_equal(expected, actual, message)
    if expected != actual
      @handshake_errors << message
    end
  end # def expected

  def valid?
    return @handshake_errors.empty?
  end # def valid?

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

  def each
    connection = @env["ftw.connection"]
    while true
      data = connection.read(16384)
      @parser.feed(data) do |payload|
        yield payload if !payload.nil?
      end
    end
  end # def each

  public(:initialize, :valid?, :rack_response, :each)
end # class FTW::WebSocket::Rack
