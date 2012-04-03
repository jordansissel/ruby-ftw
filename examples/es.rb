require "rubygems"
$: << File.join(File.dirname(__FILE__), "..", "lib")
require "ftw" # gem ftw
require "cabin" # gem cabin

agent = FTW::Agent.new

logger = Cabin::Channel.new
logger.subscribe(Logger.new(STDOUT))

worker_count = 24
queue = Queue.new
threads = worker_count.times.collect do 
  Thread.new(queue) do |queue|
    while true do
      data = queue.pop
      break if data == :quit
      request = agent.post("http://localhost:9200/foo/bar", :body => data.to_json)
      response = agent.execute(request)
      response.read_body { |a| }
    end
  end
end

10000.times do |i|
  queue << { "hello" => "world", "value" => i }
end

worker_count.times { queue << :quit }
threads.map(&:join)
