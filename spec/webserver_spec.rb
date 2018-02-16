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
        webserver_thread.kill
        fail("Webserver#run failed to return after 10s")
      end
    end

    context 'when receiving a message claiming to be an unsupported HTTP version' do
      it "doesn't crash" do
        require 'socket'

        webserver_thread = Thread.new { webserver.run }
        sleep 0.2 # wait for plugin to bind to port

        socket = TCPSocket.new('localhost', port)
        socket.write("GET / HTTP/0.9\r\n") # party like it's 1991
        socket.write("\r\n")
        socket.flush
        socket.close_write
        # nothing is written in reply, because we don't know how to support the given protocol
        expect(socket.read).to be_empty

        # server should still be alive, so send something valid to check
        socket2 = TCPSocket.new('localhost', port)
        socket2.write("GET / HTTP/1.1\r\n")
        socket2.write("\r\n")
        socket2.flush
        socket2.close_write
        expect(socket2.read).to start_with 'HTTP/1.1'

        webserver.stop
        webserver_thread.join(10) || begin
          webserver_thread.kill
          fail("Webserver#run failed to return after 10s")
        end
      end
    end
  end
end
