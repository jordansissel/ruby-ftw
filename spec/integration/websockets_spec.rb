require "fixtures/websockets"
require "rack/handler/ftw"
require "stud/try"
require "insist"

describe "WebSockets" do
  let (:logger) { Cabin::Channel.get("rspec") }
  let (:app) { Fixtures::WebEcho.new }

  let (:rack) do
    # Listen on a random port
    tries = 10
    begin
      @port = rand(20000) + 1000
      Rack::Handler::FTW.new(app, :Host => "127.0.0.1", :Port => @port)
    rescue
      tries -= 1
      retry if tries > 0
      raise
    end
  end # let rack

  let (:address) do
    rack # make the 'rack' bit go
    "localhost:#{@port}"
  end # let address

  before :all do
    logger.subscribe(STDERR)
    logger.level = :info
  end

  before :each do
    rack
    Thread.new { rack.run }
  end

  after :each do
    rack.stop
  end

  context "when using the EchoServer" do
    let (:agent) { FTW::Agent.new }

    after :each do
      agent.shutdown
    end

    subject do
      ws = nil
      Stud::try(5.times) do
        ws = agent.websocket!("http://#{address}/websocket")
        p :ws => ws
        insist { ws }.is_a?(FTW::WebSocket)
      end
      ws
    end

    it "should echo messages back over websockets" do
      iterations = 1000
      iterations.times do |i|
        message = "Hello #{i}"
        subject.publish(message)
        insist { subject.receive } == message
      end
    end
  end
end
