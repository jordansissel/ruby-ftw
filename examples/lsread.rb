# coding: utf-8
require "rubygems"
require "addressable/uri"
require "json"

$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw"
require "metriks"

agent = FTW::Agent.new
Thread.abort_on_exception = true

queue = Queue.new

threads = []
ARGV.each do |arg|
  threads << Thread.new(arg, queue) do |arg, queue|
    uri = Addressable::URI.parse(arg)
    ws = agent.websocket!(uri)
    if ws.is_a?(FTW::Response)
      puts "WebSocket handshake failed. Here's the HTTP response:"
      puts "---"
      puts ws
      exit 0
    end
    ws.each do |payload|
      next if payload.nil?
      queue << JSON.parse(payload)
    end
  end
end

seen = Hash.new { |h,k| h[k] = 0 }
count = 0
while true 
  event = queue.pop
  next unless event["@source_host"] == "seahawks"
  identity = event["@source_path"] + event["@message"]
  count += 1
  p count => event["@message"]
  #seen[identity] += 1
  #if seen[identity] > 2
    #p seen[identity] => event
  #end
end

