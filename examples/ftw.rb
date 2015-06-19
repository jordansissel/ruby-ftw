require "rubygems"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw" # gem ftw
require "cabin" # gem cabin
require "logger" # ruby stdlib

if ARGV.length != 1
  puts "Usage: #{$0} <url>" 
  exit 1
end

logger = Cabin::Channel.get
logger.level=:info
logger.subscribe(STDOUT)

agent = FTW::Agent.new
agent.configuration[FTW::Agent::SSL_VERSION] = "TLSv1.1"

ARGV.each do |url|
  logger.time("Fetch #{url}") do
    response = agent.get!(url)
    bytes = 0
    response.read_body do |chunk|
      bytes += chunk.size
    end
    logger.info("Request complete", :body_length => bytes)
  end
end
