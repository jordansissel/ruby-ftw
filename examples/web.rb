require "rubygems"
$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
require "ftw" # gem ftw

server = FTW::WebServer.new("0.0.0.0", 8888) do |request, response|
  response.status = 200
  response.body = "Hello world"
end

server.run
