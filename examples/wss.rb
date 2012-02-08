require "rubygems"
require "eventmachine"
require "em-websocket"

EventMachine.run do
  EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 8081) do |ws|
    ws.onopen do |*args|
      p :onopen => self, :args => args
      puts "WebSocket connection open"

      # publish message to the client
      ws.send "Hello Client"
    end

    ws.onclose { puts "Connection closed" }
    ws.onmessage do |msg|
      p :onmsg => self
      puts "Recieved message: #{msg}"
      ws.send msg
    end
  end
end

