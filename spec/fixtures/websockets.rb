require "sinatra/base"
require "ftw/websocket/rack"

class Fixtures; class WebEcho < Sinatra::Base
  get "/" do
    [ 200, {"Content-Type" => "text/json"}, params.to_json ]
  end

  # Make an echo server over websockets.
  get "/websocket" do
    ws = FTW::WebSocket::Rack.new(env)
    stream(:keep_open) do |out|
      ws.each do |payload|
        # 'payload' is the text payload of a single websocket message
        # publish it back to the client
        ws.publish(payload)
      end
    end
    ws.rack_response
  end
end; end # class EchoServer
