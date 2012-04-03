require "sinatra/base"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw/websocket/rack"

class Foo < Sinatra::Application
  get "/" do
    ap env
    [200, {}, "OK"]
  end

  # Make an echo server over websockets.
  get "/websocket/echo" do
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
end

run Foo.new
