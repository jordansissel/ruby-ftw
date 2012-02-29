require "awesome_print"
require "sinatra"

set :server, :FTW

get "/" do
  $stderr.puts "Hello world"
  "OK"
end

set(:protocol) do |value| 
  condition { rand <= value }
end

get "/websocket" do
  stream(:keep_open) do |out|
    # take env["ftw.connection"] and run with it.
  end
  status 101
end
