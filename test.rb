require "rubygems"
require "addressable/uri"
require "thread"

$: << File.join(File.dirname(__FILE__), "lib")
require "net-ftw" # gem net-ftw

client = Net::FTW::HTTP::Client.new
#uri = Addressable::URI.parse("http://httpbin.org/ip")
uri = Addressable::URI.parse("http://google.com/")

# 'client.get' is not the end of this api. still in progress.
client.get(uri)

# DNS Example
#dns = Net::FTW::DNS.new
#p dns.resolve("google.com")
#p dns.resolve("localhost")
#p dns.resolve("127.0.0.1")
#p dns.resolve("orange.kame.net")
##p dns.resolve("::1")

#bytes = 0
#conn = Net::FTW::Connection.new("www.google.com:80")
#conn.on(conn.class::CONNECTED) do |address|
  #conn.write("GET / HTTP/1.0\r\n\r\n")
#end
#conn.on(conn.class::DATA) do |data|
  #bytes += data.size
#end
#conn.on(conn.class::READER_CLOSED) do 
  #puts "=> Finished"
  #puts "==> Read: #{bytes}"
  #conn.disconnect
#end
#conn.on(conn.class::DISCONNECTED) do |reason, error|
  #puts "=> Disconnected: #{reason} #{error.inspect}"
#end
#conn.run
