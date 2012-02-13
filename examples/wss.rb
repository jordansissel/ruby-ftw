require "rubygems"
require "eventmachine"
require "em-websocket"
require "cabin"
require "logger"

logger = Cabin::Channel.new
logger.subscribe(Logger.new(STDOUT))

EventMachine.run do
  EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 8081) do |ws|
    ws.onopen do |*args|
      p :onopen => self, :args => args
      puts "WebSocket connection open"
    end

    ws.onclose { puts "Connection closed" }
    ws.onmessage do |msg|
      data = JSON.parse(msg)
      logger.info(data)
    end
  end
end

