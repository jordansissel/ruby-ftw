require "rubygems"
require "addressable/uri"

$: << File.join(File.dirname(__FILE__), "lib")
require "ftw/agent"

agent = FTW::Agent.new
#uri = Addressable::URI.parse("http://httpbin.org/ip")
uri = Addressable::URI.parse("http://google.com/")
#uri = Addressable::URI.parse("http://twitter.com/")

response = agent.get!(uri)
bytes = 0
response.read_body do |chunk|
  bytes += chunk.size
end
p :bytes => bytes

request = agent.head(uri)
response = agent.execute(request)
puts :body? => response.body?
