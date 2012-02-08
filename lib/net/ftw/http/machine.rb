require "net/ftw/namespace"
require "net/ftw/machine"
require "http/parser" # gem http_parser.rb

class Net::FTW::HTTP::Machine
  # States
  HEADERS = :headers
  MESSAGE = :message

  # Valid transitions
  TRANSITIONS = {
    START => HEADERS
    HEADERS => [MESSAGE, ERROR]
    MESSAGE => [START, ERROR]
  }

  def initialize
    super
    transition(HEADERS)
    @parser = HTTP::Parser.new
    @parser.on_headers_complete = proc { transition(MESSAGE) }
  end # def initialize

  def state_headers(data)
    offset = parser << data
    if state?(MESSAGE)
      # We finished headers and transitioned to message body.
      yield version, parser.status_code, parser.headers

      # Re-feed any body part we were fed that wasn't part of the headers
      feed(data[offset..-1])
    end
  end # def state_headers

  def state_message(data)
    yield data
  end # def state_message
end # class Net::FTW::HTTP::Connection
