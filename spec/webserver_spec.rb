require 'ftw/webserver'

describe "FTW Webserver" do
  describe '#run' do
    let(:webserver) { FTW::WebServer.new(host, port, &connection_handler) }
    let(:host) { 'localhost' }
    let(:port) { 9999 }

    let(:connection_handler) { Proc.new {|request, response| } }

    it 'should return when the webserver has been stopped' do
      webserver_thread = Thread.new { webserver.run }
      sleep 0.2 # wait for server to start
      webserver.stop

      webserver_thread.join(10) || begin
        fail("Webserver#run failed to return after 10s")
        webserver_thread.kill
      end
    end
  end
end
