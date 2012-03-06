# For The Web

## Getting Started

* For web agents: {FTW::Agent}
* For dns: {FTW::DNS}
* For tcp connections: {FTW::Connection}
* For tcp servers: {FTW::Server}

## Overview

net/http is pretty much not good. Additionally, DNS behavior in ruby changes quite frequently.

I primarily want two things in both client and server operations:

* A consistent API with good documentation, readable code, and high quality tests.
* Modern web features: websockets, spdy, etc.

Desired features:

* Awesome documentation
* A HTTP client that acts as a full user agent, not just a single connections. (With connection reuse)
* HTTP and SPDY support.
* WebSockets support.
* SSL/TLS support.
* Browser Agent features like cookies and caching
* An API that lets me do what I need.
* Server and Client modes.
* Support for both normal operation and EventMachine would be nice.

For reference:

* [DNS in Ruby stdlib is broken](https://github.com/jordansissel/experiments/tree/master/ruby/dns-resolving-bug), so I need to provide my own DNS api.

## Agent API

Reference: {FTW::Agent}

### Common case

    agent = FTW::Agent.new

    request = agent.get("http://www.google.com/")
    response = request.execute
    puts response.body.read

    # Simpler
    response = agent.get!("http://www.google.com/").read
    puts response.body.read

### SPDY

* This is not implemented yet

SPDY should automatically be attempted. The caller should be unaware.

I do not plan on exposing any direct means for invoking SPDY.

### WebSockets

    # 'http(s)' or 'ws(s)' urls are valid here. They will mean the same thing.
    websocket = agent.websocket!("http://somehost/endpoint")

    websocket.publish("Hello world")
    websocket.each do |message|
      puts :received => message
    end

## Web Server API

I have implemented a rack server, Rack::Handler::FTW. It does not comply fully
with the Rack spec. See 'Rack Compliance Issues' below.

Under the FTW rack handler, there is an environment variable added,
"ftw.connection". This will be a FTW::Connection you can use for CONNECT,
Upgrades, etc. 

There's also a websockets wrapper, FTW::WebSockets::Rack, that will help you
specifically with websocket requests and such.

## Rack Compliance issues

Due to some awkward and bad requirements - specifically those around the
specified behavior of 'rack.input' - I can't support the rack specification fully.

The 'rack.input' must be an IO-like object supporting #rewind which rewinds to
the beginning of the request.

For high-data connections (like uploads, HTTP CONNECT, and HTTP Upgrade), it's
not practical to hold the entire history of time in a buffer. We'll run out of
memory, you crazy fools!

Details here: https://github.com/rack/rack/issues/347

## Other Projects

Here are some related projects that I have no affiliation with:

* https://github.com/igrigorik/em-websocket - websocket server for eventmachine
* https://github.com/faye/faye - pubsub for the web (includes a websockets implementation)
* https://github.com/faye/faye-websocket-ruby - websocket client and server in ruby
* https://github.com/lifo/cramp - real-time web framework (async, websockets)
* https://github.com/igrigorik/em-http-request - HTTP client for EventMachine
* https://github.com/geemus/excon - http client library

Given some of the above (especially the server-side stuff), I'm likely try and integrate
with those projects. For example, writing a Faye handler that uses the FTW server, if the
FTW web server even stays around.
