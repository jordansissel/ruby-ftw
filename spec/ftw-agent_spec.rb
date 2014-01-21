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

  context "ssl strength" do
    let (:agent) { FTW::Agent.new }

    it "should pass howsmyssl's tests" do
      response = agent.get!("https://www.howsmyssl.com/a/check")
      reject { response }.error?
      payload = response.read_body
      require "json"
      result = JSON.parse(payload)
      insist { result["beast_vuln"] } == false
      insist { result["rating"] } != "Bad"
    end
  end
end

