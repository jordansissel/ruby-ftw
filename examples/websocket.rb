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
ws.publish({ :foo => :bar}.to_json)
ws.each do |payload|
  p :payload => payload
end
