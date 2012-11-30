# coding: utf-8
require "rubygems"
require "addressable/uri"

$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw"

agent = FTW::Agent.new

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

require "metriks"

#meter = Metriks.meter("events")
start = Time.now
count = 0

screen = []
metrics = Hash.new do |h, k| 
  m = Metriks.meter(k)
  screen << m
  h[k] = m
end

blocks = []
%w{ ░ ▒ ▓ █ }.each_with_index do |block, i|

  # bleed over on some colors because a block[n] at color m is much darker than block[n+1] 
  8.times do |v|
    color = (i * 6) + v + 232
    break if color > 256
    blocks << "\x1b[38;5;#{color}m#{block}\x1b[0m"
  end
end
puts blocks.join("")

#.collect do |tick|
  ## 256 color support, use grayscale
  #24.times.collect do |shade|
    # '38' is foreground
    # '48' is background
    # Grey colors start at 232, but let's use the brighter half.
    # escape [ 38 ; 5 ; <color>
    #"\x1b[38;5;#{232 + 12 + 2 * shade}m#{tick}\x1b[0m"
  #end
  #tick
#end.flatten

overall = Metriks.meter("-overall-")
start = Time.now
while true
  event = queue.pop
  host = event["@source_host"]
  metrics[host].mark
  overall.mark

  if Time.now - start > 1
    #rates = metrics.collect do |host, metric|
    rates = screen.collect { |m| m.one_minute_rate }
    max = rates.max
    start = Time.now
    next if max == 0

    top5 = metrics.sort_by { |k,m| m.one_minute_rate }[-5..-1]

    $stdout.write("\x1b[H\x1b[2J")
    puts "Hosts: #{rates.count}"
    puts "Overall rate: #{overall.one_minute_rate}"
    puts "Top 5: #{top5.reverse.collect { |host, metric| "#{host}(#{"%.2f" % metric.one_minute_rate})" }.join(", ") }"
    # Dump each rate as a single character based on the value.
    $stdout.write(rates.collect { |rate| blocks[ (blocks.size * (rate / max)).floor ] }.join(""))
  end
end
