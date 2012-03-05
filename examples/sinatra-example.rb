require "sinatra"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw/websocket/rack"

# Using the FTW rack server is required for this websocket support.
set :server, :FTW

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
