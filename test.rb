require "rubygems"
require "addressable/uri"

$: << File.join(File.dirname(__FILE__), "lib")
require "net-ftw" # gem net-ftw

client = Net::FTW::HTTP::Client.new
uri = Addressable::URI.parse("http://httpbin.org/ip")
#client.get(uri) do |req, resp|
  #p req
#end

dns = Net::FTW::DNS.new
p dns.resolve("google.com")
p dns.resolve("localhost")
p dns.resolve("127.0.0.1")
p dns.resolve("orange.kame.net")
p dns.resolve("::1")
