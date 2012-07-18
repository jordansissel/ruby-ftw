require "ftw"

$stdout.sync = true
server = FTW::WebServer.new("0.0.0.0", ENV["PORT"].to_i || 8888) do |request, response|
  puts request.headers

  request.read_body do |chunk|
    puts "Chunk: #{chunk.inspect}"
  end

  response.status = 200
  response.body = "Done!"
end

server.run

