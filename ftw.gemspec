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
  spec.summary = "For The Web. HTTP, WebSockets, SPDY, etc."
  spec.description = "Trying to build a solid and sane API for client and server web stuff."
  spec.license = "Apache License (2.0)"

  gem "json", "1.6.5" # for json
  gem "cabin", ">0" # for logging, latest is fine for now
  gem "http_parser.rb", "0.5.3" # for http request/response parsing
  gem "addressable", "2.2.6"  # because stdlib URI is terrible
  gem "backport-bij", "1.0.1" # for hacking stuff in to ruby <1.9
  gem "minitest", ">0" # for unit tests, latest of this is fine


  spec.files = files
  spec.require_paths << "lib"
  #spec.bindir = "bin"

  spec.authors = ["Jordan Sissel"]
  spec.email = ["jls@semicomplete.com"]
  spec.homepage = "http://github.com/jordansissel/ruby-ftw"
end

