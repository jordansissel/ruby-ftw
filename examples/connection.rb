require "rubygems"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw" # gem ftw

connection = FTW::Connection.new(ARGV[0])
tries = 4
tries.times do
  error = connection.connect
  p error
  break if error.nil?
end

p connection.connected?
