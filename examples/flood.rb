require "rubygems"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw" # gem ftw
require "benchmark"

if ARGV.length != 1
  puts "Usage: #{$0} <url>" 
  exit 1
end

agent = FTW::Agent.new
url = ARGV[0]

loop do
  result =  Benchmark.measure do
    response = agent.get!(url)
    bytes = 0
    response.read_body do |chunk|
      bytes += chunk.size
    end
  end
  puts result
end
