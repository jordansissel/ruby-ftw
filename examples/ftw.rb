require "rubygems"
require "ftw" # gem ftw
require "cabin" # gem cabin
require "logger" # ruby stdlib

if ARGV.length != 1
  puts "Usage: #{$0} <url>" 
  exit 1
end

agent = FTW::Agent.new
url = ARGV[0]

logger = Cabin::Channel.new
logger.subscribe(Logger.new(STDOUT))

# Fetch the url 5 times, demonstrating connection reuse, etc.
5.times do
  logger.time("Fetch #{url}") do
    response = agent.get!(url)
    bytes = 0
    response.read_body do |chunk|
      bytes += chunk.size
    end
    logger.info("Request complete", :body_length => bytes)
  end

  # Be nice, slow down.
  sleep 1
end
