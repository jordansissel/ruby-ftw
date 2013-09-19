require "ftw/namespace"
require "ftw/crlf"
require "cabin"
require "logger"

# This module provides web protocol handling as a mixin.
module FTW::Protocol
  include FTW::CRLF

  # Read an HTTP message from a given connection
  #
  # This method blocks until a full http message header has been consumed
  # (request *or* response)
  #
  # The body of the message, if any, will not be consumed, and the read
  # position for the connection will be left at the end of the message headers.
  # 
  # The 'connection' object must respond to #read(timeout) and #pushback(string)
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
      data = connection.read(16384)

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

  def write_http_body(body, io, chunked=false)
    if chunked
      write_http_body_chunked(body, io)
    else
      write_http_body_normal(body, io)
    end
  end # def write_http_body

  # Encode the given text as in 'chunked' encoding.
  def encode_chunked(text)
    return sprintf("%x%s%s%s", text.bytesize, CRLF, text, CRLF)
  end # def encode_chunked

  def write_http_body_chunked(body, io)
    if body.is_a?(String)
      io.write(encode_chunked(body))
    elsif body.respond_to?(:sysread)
      true while io.write(encode_chunked(body.sysread(16384)))
    elsif body.respond_to?(:read)
      true while io.write(encode_chunked(body.read(16384)))
    elsif body.respond_to?(:each)
      body.each { |s| io.write(encode_chunked(s)) }
    end

    # The terminating chunk is an empty one.
    io.write(encode_chunked(""))
  end # def write_http_body_chunked

  def write_http_body_normal(body, io)
    if body.is_a?(String)
      io.write(body)
    elsif body.respond_to?(:read)
      true while io.write(body.read(16384))
    elsif body.respond_to?(:each)
      body.each { |s| io.write(s) }
    end
  end # def write_http_body_normal

  # Read the body of this message. The block is called with chunks of the
  # response as they are read in.
  #
  # This method is generally only called by http clients, not servers.
  def read_http_body(&block)
    if @body.respond_to?(:read)
      if headers.include?("Content-Length") and headers["Content-Length"].to_i > 0
        @logger.debug("Reading body with Content-Length")
        read_http_body_length(headers["Content-Length"].to_i, &block)
      elsif headers["Transfer-Encoding"] == "chunked"
        @logger.debug("Reading body with chunked encoding")
        read_http_body_chunked(&block)
      end

      # If this is a poolable resource, release it (like a FTW::Connection)
      @body.release if @body.respond_to?(:release)
    elsif !@body.nil?
      block.call(@body)
    end
  end # def read_http_body

  # Read the body of this message. The block is called with chunks of the
  # response as they are read in.
  #
  # This method is generally only called by http clients, not servers.
  #
  # If no block is given, the entire response body is returned as a string.
  def read_body(&block)
    if !block_given?
      content = ""
      read_http_body { |chunk| content << chunk }
      return content
    else
      read_http_body(&block)
    end
  end # def read_body

  # A shorthand for discarding the body of a request or response.
  #
  # This is the same as:
  #
  #     foo.read_body { |c| }
  def discard_body
    read_body { |c| }
  end # def discard_body

  # Read the length bytes from the body. Yield each chunk read to the block
  # given. This method is generally only called by http clients, not servers.
  def read_http_body_length(length, &block)
    remaining = length
    while remaining > 0
      data = @body.read(remaining)
      @logger.debug("Read bytes", :length => data.bytesize)
      if data.bytesize > remaining
        # Read too much data, only wanted part of this. Push the rest back.
        yield data[0..remaining]
        remaining = 0
        @body.pushback(data[remaining .. -1]) if remaining < 0
      else
        yield data
        remaining -= data.bytesize
      end
    end
  end # def read_http_body_length

  # This is kind of messed, need to fix it.
  def read_http_body_chunked(&block)
    parser = HTTP::Parser.new

    # Fake fill-in the response we've already read into the parser.
    parser << to_s
    parser << CRLF
    parser.on_body = block
    done = false
    parser.on_message_complete = proc { done = true }

    while !done # will break on special conditions below
      # TODO(sissel): In JRuby, this read will sometimes hang for ever
      # because there's some wonkiness in IO.select on SSLSockets in JRuby.
      # Maybe we should fix it... 
      data = @body.read
      offset = parser << data
      if offset != data.length
        raise "Parser did not consume all data read?"
      end
    end
  end # def read_http_body_chunked
end # module FTW::Protocol
