require "sinatra/base"
$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
require "ftw/websocket/rack"
require "cabin"

class App < Sinatra::Base
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

# Run the sinatra app in another thread
require "rack/handler/ftw"
Thread.new do
  Rack::Handler::FTW.run(App.new, :Host => "0.0.0.0", :Port => 8080)
end

logger = Cabin::Channel.get
logger.level = :info
logger.subscribe(STDOUT)

agent = FTW::Agent.new
ws = agent.websocket!("http://127.0.0.1:8080/websocket/echo")
ws.publish("Hello")
ws.each do |message|
  p message
end
