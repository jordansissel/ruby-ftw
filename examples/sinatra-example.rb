require "sinatra"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw/websocket/rack"


set :server, :FTW

get "/" do
  $stderr.puts "Hello world"
  "OK"
end

set(:protocol) do |value| 
  condition { rand <= value }
end

get "/websocket" do
  ws = FTW::WebSocket::Rack.new(env)
  stream(:keep_open) do |out|
    # take env["ftw.connection"] and run with it.
    begin
      ws.each do |payload|
        # TODO(sissel): Implement publishing.
        ws.publish(payload)
      end
    rescue => e
      puts "Exception => " + e.inspect
      #puts e.backtrace.map { |b| " => #{b}\n" }
      out.close
    end
  end

  p :response => ws.rack_response
  ws.rack_response
end
