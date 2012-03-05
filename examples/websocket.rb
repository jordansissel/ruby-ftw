require "rubygems"
require "addressable/uri"

$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw"

agent = FTW::Agent.new
uri = Addressable::URI.parse(ARGV[0])
ws = agent.websocket!(uri)
if ws.is_a?(FTW::Response)
  puts "WebSocket handshake failed. Here's the HTTP response:"
  puts "---"
  puts ws
  exit 0
end

iterations = 100000

# Start a thread to publish messages over the websocket
Thread.new do 
  iterations.times do |i|
    ws.publish({ "time" => Time.now.to_f}.to_json)
  end
end

count = 0
start = Time.now

# For each message, keep a count and report the rate of messages coming in.
ws.each do |payload|
  data = JSON.parse(payload)
  count += 1

  if count % 5000 == 0
    p :rate => (count / (Time.now - start)), :total => count
    break if count == iterations
  end
end
