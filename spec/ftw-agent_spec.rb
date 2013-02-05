require "cabin"
require "ftw/agent"

describe "FTW Agent for client request" do
  let (:logger) { Cabin::Channel.get("rspec") }

  before :all do
    logger.subscribe(STDERR)
    logger.level = :info
  end

  context "when re-using connection" do
    let (:agent) { FTW::Agent.new }

    after :each do
      agent.shutdown
    end

    #This test currently fail
    it "should not fail on SSL EOF error" do
      url = "https://logstash.objects.dreamhost.com/"
      response = agent.get!(url)
      # Consume body to let this connection be reused
      response.read_body
      #Re-use connection
      response = agent.get!(url)
      # Consume body to let this connection be reused
      response.read_body
    end
  end
end

