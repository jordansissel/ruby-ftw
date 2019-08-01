$: << File.join(File.dirname(__FILE__), "lib")
require "ftw/version" # For FTW::VERSION

Gem::Specification.new do |spec|
  files = []
  paths = %w{lib test README.md}
  paths.each do |path|
    if File.file?(path)
      files << path
    else
      files += Dir["#{path}/**/*"]
    end
  end

  spec.name = "ftw"
  spec.version = FTW::VERSION
  spec.description = "For The Web. Trying to build a solid and sane API for client and server web stuff. Client and Server operations for HTTP, WebSockets, SPDY, etc."
  spec.summary = spec.description
  spec.license = "Apache License (2.0)"

  spec.add_dependency("cabin", ">0") # for logging, latest is fine for now
  spec.add_dependency("http_parser.rb", "~> 0.6") # for http request/response parsing
  spec.add_dependency("addressable", ">= 2.4")  # because stdlib URI is terrible
  spec.add_dependency("backports", ">= 2.6.2") # for hacking stuff into ruby <1.9
  spec.add_development_dependency("minitest", ">0") # for unit tests, latest of this is fine

  spec.files = files
  spec.require_paths << "lib"
  #spec.bindir = "bin"

  spec.authors = ["Jordan Sissel"]
  spec.email = ["jls@semicomplete.com"]
  spec.homepage = "http://github.com/jordansissel/ruby-ftw"
end
