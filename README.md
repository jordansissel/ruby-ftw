# For The Web

net/http is pretty much not good.

I want:

* A HTTP client that acts as a full user agent, not just a single connection.
* HTTP and SPDY support.
* WebSockets support.
* SSL/TLS support.
* An API that lets me do what I need.
* Server and Client modes.
* Support for both normal operation and EventMachine would be nice.

## DONE

* TCP connection 
* DNS resolution (wraps Socket.gethostname)
* HTTP client partially done

## TODO

* Tests, yo.
* Logging, yo. With cabin, obviously.
* [DNS in Ruby stdlib is broken](https://github.com/jordansissel/experiments/tree/master/ruby/dns-resolving-bug), I need to write my own
