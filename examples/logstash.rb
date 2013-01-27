# coding: utf-8
require "rubygems"
require "addressable/uri"
require "date"

$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw"

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

ages = Hash.new do |h, k| 
  screen << k
  h[k] = 0
end

blocks = []
%w{ ░ ▒ ▓ █ }.each_with_index do |block, i|

  # bleed over on some colors because a block[n] at color m is much darker than block[n+1] 
  8.times do |v|
    color = (i * 6) + v + 232
    break if color >= 256
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

#overall = Metriks.meter("-overall-")
start = Time.now
#fakehost = Hash.new { |h,k| h[k] = "fringe#{rand(1000)}" }
count = 0
while true
  event = queue.pop
  count += 1
  host = event["@source_host"]
  #host = fakehost[event["@source_host"]]

  now = Time.now
  ages[host] # lame hack to append to screen
  ages[host] = now - DateTime.parse(event["@timestamp"]).to_time

  if count > 10000
    count = 0
    # on-screen-order values
    sov = screen.collect { |host| ages[host] }
    max = sov.max
    start = Time.now
    next if max == 0

    $stdout.write("\x1b[H\x1b[2J")
    puts "Hosts: #{ages.count}"
    worst5 = ages.sort_by { |k,v| -v }[0..5]
    puts "Worst 5 (hours): #{worst5.collect { |host, value| "#{host}(#{"%.1f" % (value / 60.0 / 60)})" }.join(", ") }"

    # Write the legend
    $stdout.write("Legend: ");
    (0..5).each do |i|
      v = (i * (max / 5.0))
      block = blocks[((blocks.size - 1) * (i / 5.0)).floor]
      $stdout.write("%s %0.2f     " % [block, v/60/60.0])
    end
    puts
    $stdout.write(sov.collect do |value| 
      if value < 0
        "\x1b[1;46m⚉\x1b[0m"
      else
        blocks[ ((blocks.size) * (value / max)).floor ] 
      end
    end.join(""))
  end
end
