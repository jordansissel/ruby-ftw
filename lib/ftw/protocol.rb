require "ftw/namespace"
require "cabin"
require "logger"

module FTW::Protocol
  # Read an HTTP message from a given connection
  #
  # This method will stop immediately after reading the full message header. No
  # body will be consumed.
  def read_http_message(connection)
    parser = HTTP::Parser.new
    headers_done = false
    parser.on_headers_complete = proc { headers_done = true; :stop }

    # headers_done will be set to true when parser finishes parsing the http
    # headers for this request
    while !headers_done
      # TODO(sissel): This read could toss an exception of the server aborts
      # prior to sending the full headers. Figure out a way to make this happy.
      # Perhaps fabricating a 500 response?
      data = connection.read

      # Feed the data into the parser. Offset will be nonzero if there's 
      # extra data beyond the header.
      offset = parser << data
    end

    # If we consumed part of the body while parsing headers, put it back
    # onto the connection's read buffer so the next consumer can use it.
    if offset < data.length
      connection.pushback(data[offset .. -1])
    end

    # This will have an 'http_method' if it's a request
    if !parser.http_method.nil?
      # have http_method, so this is an HTTP Request message
      request = FTW::Request.new
      request.method = parser.http_method
      request.request_uri = parser.request_url
      request.version = "#{parser.http_major}.#{parser.http_minor}".to_f
      parser.headers.each { |field, value| request.headers.add(field, value) }
      return request
    else
      # otherwise, no http_method, so this is an HTTP Response message
      response = FTW::Response.new
      response.version = "#{parser.http_major}.#{parser.http_minor}".to_f
      response.status = parser.status_code
      parser.headers.each { |field, value| response.headers.add(field, value) }
      return response
    end
  end # def read_http_message

  public(:read_http_message)
end # module FTW::Protocol
