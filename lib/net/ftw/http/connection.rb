require "net/ftw/namespace"
require "net/ftw/connection"

class Net::FTW::HTTP::Connection < Net::FTW::Connection
  HEADERS_COMPLETE = :headers_complete
  MESSAGE_BODY = :message_body

  def run
    # TODO(sissel): Implement retries on certain failures like DNS, connect
    # timeouts, or connection resets?
    # TODO(sissel): use HTTPS if the uri.scheme == "https"
    # TODO(sissel): Resolve the hostname
    # TODO(sissel): Start a new connection, or reuse an existing one.
    #
    # TODO(sissel): This suff belongs in a new class, like HTTP::Connection or something.
    parser = HTTP::Parser.new

    # Only parse the header of the response
    state = :headers
    parser.on_headers_complete = proc { state = :body; :stop }

    on(DATA) do |data|
      # TODO(sissel): Implement this better. Should be able to swap out the
      # DATA handler at run-time
      if state == :headers
        offset = parser << data
        if state == :body
          # headers done parsing.
          version = "#{parser.http_major}.#{parser.http_minor}".to_f
          trigger(HEADERS_COMPLETE, version, parser.status_code, parser.headers)

          # Re-call 'data' with the remaining non-header portion of data.
          trigger(DATA, data[offset..-1])
        end
      else
        trigger(MESSAGE_BODY, data)
      end
    end

    super()
  end # def run
end # class Net::FTW::HTTP::Connection
