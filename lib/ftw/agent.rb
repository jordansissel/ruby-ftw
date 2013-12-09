require "ftw/namespace"
require "ftw/request"
require "ftw/connection"
require "ftw/protocol"
require "ftw/pool"
require "ftw/websocket"
require "addressable/uri"
require "cabin"
require "openssl"

# This should act as a proper web agent.
#
# * Reuse connections.
# * SSL/TLS.
# * HTTP Upgrade support.
# * HTTP 1.1 (RFC2616).
# * WebSockets (RFC6455).
# * Support Cookies.
#
# All standard HTTP methods defined by RFC2616 are available as methods on 
# this agent: get, head, put, etc.
#
# Example:
#
#     agent = FTW::Agent.new
#     request = agent.get("http://www.google.com/")
#     response = agent.execute(request)
#     puts response.body.read
#
# For any standard http method (like 'get') you can invoke it with '!' on the end
# and it will execute and return a FTW::Response object:
#
#     agent = FTW::Agent.new
#     response = agent.get!("http://www.google.com/")
#     puts response.body.head
#
# TODO(sissel): TBD: implement cookies... delicious chocolate chip cookies.
class FTW::Agent
  include FTW::Protocol
  require "ftw/agent/configuration"
  include FTW::Agent::Configuration

  # Thrown when too many redirects are encountered
  # See also {FTW::Agent::Configuration::REDIRECTION_LIMIT}
  class TooManyRedirects < StandardError
    attr_accessor :response
    def initialize(reason, response)
      super(reason)
      @response = response
    end
  end

  # List of standard HTTP methods described in RFC2616
  STANDARD_METHODS = %w(options get head post put delete trace connect)

  # Everything is private by default.
  # At the bottom of this class, public methods will be declared.
  private

  def initialize
    @pool = FTW::Pool.new
    @logger = Cabin::Channel.get

    configuration[REDIRECTION_LIMIT] = 20

    need_ssl_ca_certs = true

    @certificate_store = OpenSSL::X509::Store.new
    if File.readable?(OpenSSL::X509::DEFAULT_CERT_FILE)
      @logger.debug("Adding default certificate file",
                    :path => OpenSSL::X509::DEFAULT_CERT_FILE)
      begin
        @certificate_store.add_file(OpenSSL::X509::DEFAULT_CERT_FILE)
        need_ssl_ca_certs = false
      rescue OpenSSL::X509::StoreError => e
        # Work around jruby#1055 "Duplicate extensions not allowed"
        @logger.warn("Failure loading #{OpenSSL::X509::DEFAULT_CERT_FILE}. " \
                     "Will try another cacert source.")
      end
    end

    if need_ssl_ca_certs
      # Use some better defaults from http://curl.haxx.se/docs/caextract.html
      # Can we trust curl's CA list? Global ssl trust is a tragic joke, anyway :\
      @logger.info("Using upstream ssl ca certs from curl. Possibly untrustworthy.")
      default_ca = File.join(File.dirname(__FILE__), "cacert.pem")

      # JRUBY-6870 - strip 'jar:' prefix if it is present.
      if default_ca =~ /^jar:file.*!/
        default_ca.gsub!(/^jar:/, "")
      end
      @certificate_store.add_file(default_ca)
    end

    # Handle the local user/app trust store as well.
    if File.directory?(configuration[SSL_TRUST_STORE])
      # This is a directory, so use add_path
      @logger.debug("Adding SSL_TRUST_STORE",
                    :path => configuration[SSL_TRUST_STORE])
      @certificate_store.add_path(configuration[SSL_TRUST_STORE])
    end

    # TODO(sissel): Add custom paths for ssl certs
  end # def initialize

  # Verify a certificate.
  #
  # host => the host (string)
  # port => the port (number)
  # verified => true/false, was this cert verified by our certificate store?
  # context => an OpenSSL::SSL::StoreContext
  def certificate_verify(host, port, verified, context)
    # Now verify the entire chain.
    begin
      @logger.debug("Verify peer via OpenSSL::X509::Store",
                    :verified => verified, :chain => context.chain.collect { |c| c.subject },
                    :context => context, :depth => context.error_depth,
                    :error => context.error, :string => context.error_string)
      # Untrusted certificate; prompt to accept if possible.
      if !verified and STDOUT.tty?
        # TODO(sissel): Factor this out into a verify callback where this
        # happens to be the default.

        puts "Untrusted certificate found; here's what I know:"
        puts "  Why it's untrusted: (#{context.error}) #{context.error_string}"

        if context.error_string =~ /local issuer/
          puts "  Missing cert for issuer: #{context.current_cert.issuer}"
          puts "  Issuer hash: #{context.current_cert.issuer.hash.to_s(16)}"
        else
          puts "  What you think it's for: #{host} (port #{port})"
          cn = context.chain[0].subject.to_s.split("/").grep(/^CN=/).first.split("=",2).last rescue "<unknown, no CN?>"
          puts "  What it's actually for: #{cn}"
        end

        puts "  Full chain:"
        context.chain.each_with_index do |cert, i|
          puts "    Subject(#{i}): [#{cert.subject.hash.to_s(16)}] #{cert.subject}"
        end
        print "Trust? [(N)o/(Y)es/(P)ersistent] "

        system("stty raw")
        answer = $stdin.getc.downcase
        system("stty sane")
        puts

        if ["y", "p"].include?(answer)
          # TODO(sissel): Factor this out into Agent::Trust or somesuch
          context.chain.each do |cert|
            # For each certificate, add it to the in-process certificate store.
            begin
              @certificate_store.add_cert(cert)
            rescue OpenSSL::X509::StoreError => e
              # If the cert is already trusted, move along.
              if e.to_s != "cert already in hash table" 
                raise # this is a real error, reraise.
              end
            end

            # TODO(sissel): Factor this out into Agent::Trust or somesuch
            # For each certificate, if persistence is requested, write the cert to
            # the configured ssl trust store (usually ~/.ftw/ssl-trust.db/) 
            if answer == "p" # persist this trusted cert
              require "fileutils"
              if !File.directory?(configuration[SSL_TRUST_STORE])
                FileUtils.mkdir_p(configuration[SSL_TRUST_STORE])
              end

              # openssl verify recommends the 'ca path' have files named by the
              # hashed subject name. Turns out openssl really expects the
              # hexadecimal version of this.
              name = File.join(configuration[SSL_TRUST_STORE], cert.subject.hash.to_s(16))
              # Find a filename that doesn't exist.
              num = 0
              num += 1 while File.exists?("#{name}.#{num}")

              # Write it out
              path = "#{name}.#{num}"
              @logger.info("Persisting certificate", :subject => cert.subject, :path => path)
              File.write(path, cert.to_pem)
            end # if answer == "p"
          end # context.chain.each
          return true
        end # if answer was "y" or "p"
      end # if !verified and stdout is a tty

      return verified
    rescue => e
      # We have to rescue all and emit because openssl verify_callback ignores
      # exceptions silently
      @logger.error(e)
      return verified
    end
  end # def certificate_verify

  # Define all the standard HTTP methods (Per RFC2616)
  # As an example, for "get" method, this will define these methods:
  # 
  # * FTW::Agent#get(uri, options={})
  # * FTW::Agent#get!(uri, options={})
  #
  # The first one returns a FTW::Request you must pass to Agent#execute(...)
  # The second does the execute for you and returns a FTW::Response.
  # 
  # For a full list of these available methods, see STANDARD_METHODS.
  #
  STANDARD_METHODS.each do |name|
    m = name.upcase

    # 'def get' (put, post, etc)
    define_method(name.to_sym) do |uri, options={}|
      return request(m, uri, options)
    end

    # 'def get!' (put!, post!, etc)
    define_method("#{name}!".to_sym) do |uri, options={}|
      return execute(request(m, uri, options))
    end
  end # STANDARD_METHODS.each

  # Send the request as an HTTP upgrade.
  # 
  # Returns the response and the FTW::Connection for this connection.
  # If the upgrade was denied, the connection returned will be nil.
  def upgrade!(uri, protocol, options={})
    req = request("GET", uri, options)
    req.headers["Connection"] = "Upgrade"
    req.headers["Upgrade"] = protocol
    response = execute(req)
    if response.status == 101
      # Success, return the response object and the connection to hand off.
      return response, response.body
    else
      return response, nil
    end
  end # def upgrade!

  # Make a new websocket connection.
  #
  # This will send the http request. If the websocket handshake
  # is successful, a FTW::WebSocket instance will be returned.
  # Otherwise, a FTW::Response will be returned.
  #
  # See {#request} for what the 'uri' and 'options' parameters should be.
  def websocket!(uri, options={})
    # TODO(sissel): Use FTW::Agent#upgrade! ?
    req = request("GET", uri, options)
    ws = FTW::WebSocket.new(req)
    response = execute(req)
    if ws.handshake_ok?(response)
      # response.body is a FTW::Connection
      ws.connection = response.body

      # There seems to be a bug in http_parser.rb where websocket responses
      # lead with a newline for some reason.  It's like the header terminator
      # CRLF still has the LF character left in the buffer. Work around it.
      data = response.body.read
      if data[0] == "\n"
        response.body.pushback(data[1..-1])
      else
        response.body.pushback(data)
      end

      return ws
    else
      return response
    end
  end # def websocket!

  # Build a request. Returns a FTW::Request object.
  #
  # Arguments:
  #
  # * method - the http method
  # * uri - the URI to make the request to
  # * options - a hash of options
  #
  # uri can be a valid url or an Addressable::URI object.
  # The uri will be used to choose the host/port to connect to. It also sets
  # the protocol (https, etc). Further, it will set the 'Host' header.
  #
  # The 'options' hash supports the following keys:
  # 
  # * :headers => { string => string, ... }. This allows you to set header values.
  def request(method, uri, options)
    @logger.info("Creating new request", :method => method, :uri => uri, :options => options)
    request = FTW::Request.new(uri)
    request.method = method
    request.headers.add("Connection", "keep-alive")

    if options.include?(:headers)
      options[:headers].each do |key, value|
        request.headers.add(key, value)
      end
    end

    if options.include?(:body)
      request.body = options[:body]
    end

    return request
  end # def request

  # Execute a FTW::Request in this Agent.
  #
  # If an existing, idle connection is already open to the target server
  # of this Request, it will be reused. Otherwise, a new connection
  # is opened.
  #
  # Redirects are always followed.
  #
  # @param [FTW::Request]
  # @return [FTW::Response] the response for this request.
  def execute(request)
    # TODO(sissel): Make redirection-following optional, but default.

    tries = 3
    begin
      connection, error = connect(request.headers["Host"], request.port,
                                  request.protocol == "https")
      if !error.nil?
        p :error => error
        raise error
      end
      response = request.execute(connection)
    rescue EOFError => e
      tries -= 1
      @logger.warn("Error while sending request, will retry.",
                   :tries_left => tries,
                   :exception => e)
      retry if tries > 0
    end

    redirects = 0
    # Follow redirects
    while response.redirect? and response.headers.include?("Location")
      # RFC2616 section 10.3.3 indicates HEAD redirects must not include a
      # body. Otherwise, the redirect response can have a body, so let's
      # throw it away.
      if request.method == "HEAD" 
        # Head requests have no body
        connection.release
      elsif response.content?
        # Throw away the body
        response.body = connection
        # read_body will consume the body and release this connection
        response.read_http_body { |chunk| }
      end

      # TODO(sissel): If this response has any cookies, store them in the
      # agent's cookie store

      redirects += 1
      if redirects > configuration[REDIRECTION_LIMIT]
        # TODO(sissel): include original a useful debugging information like
        # the trace of redirections, etc.
        raise TooManyRedirects.new("Redirect more than " \
            "#{configuration[REDIRECTION_LIMIT]} times, aborting.", response)
        # I don't like this api from FTW::Agent. I think 'get' and other methods
        # should return (object, error), and if there's an error 
      end

      @logger.debug("Redirecting", :location => response.headers["Location"])
      request.use_uri(response.headers["Location"])
      connection, error = connect(request.headers["Host"], request.port, request.protocol == "https")
      # TODO(sissel): Do better error handling than raising.
      if !error.nil?
        p :error => error
        raise error
      end
      response = request.execute(connection)
    end # while being redirected

    # RFC 2616 section 9.4, HEAD requests MUST NOT have a message body.
    if request.method != "HEAD"
      response.body = connection
    else
      connection.release
    end
   
    # TODO(sissel): If this response has any cookies, store them in the
    # agent's cookie store
    return response
  end # def execute

  # shutdown this agent.
  #
  # This will shutdown all active connections.
  def shutdown
    @pool.each do |identifier, list|
      list.each do |connection|
        connection.disconnect("stopping agent")
      end
    end
  end # def shutdown

  # Returns a FTW::Connection connected to this host:port.
  def connect(host, port, secure=false)
    address = "#{host}:#{port}"
    @logger.debug("Fetching from pool", :address => address)
    error = nil

    connection = @pool.fetch(address) do
      @logger.info("New connection to #{address}")
      connection = FTW::Connection.new(address)
      error = connection.connect
      if !error.nil?
        # Return nil to the pool, so like, we failed..
        nil
      else
        # Otherwise return our new connection
        connection
      end
    end

    if !error.nil?
      @logger.error("Connection failed", :destination => address, :error => error)
      return nil, error
    end

    @logger.debug("Pool fetched a connection", :connection => connection)
    connection.mark

    if secure
      # Curry a certificate_verify callback for this connection.
      verify_callback = proc do |verified, context|
        begin
          certificate_verify(host, port, verified, context)
        rescue => e
          @logger.error("Error in certificate_verify call", :exception => e)
        end
      end
      connection.secure(:certificate_store => @certificate_store,
                        :verify_callback => verify_callback)
    end # if secure

    return connection, nil
  end # def connect

  # TODO(sissel): Implement methods for managing the certificate store
  # TODO(sissel): Implement methods for managing the cookie store
  # TODO(sissel): Implement methods for managing the cache
  # TODO(sissel): Implement configuration stuff? Is FTW::Agent::Configuration the best way?
  public(:initialize, :execute, :websocket!, :upgrade!, :shutdown, :request)
end # class FTW::Agent
