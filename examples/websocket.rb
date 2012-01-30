require "rubygems"
require "addressable/uri"

$: << File.join(File.dirname(__FILE__), "..", "lib")
require "net-ftw" # gem net-ftw

ws = Net::FTW::WebSocket.new(ARGV[0])
