require "rubygems"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw" # gem ftw
require "cabin" # gem cabin
require "logger" # ruby stdlib

server = FTW::Server.new("localhost:8080")

server.each_connection do |connection|
  connection.write("Hello")
  connection.disconnect("normal")
end
