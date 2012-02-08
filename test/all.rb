require "rubygems"
require "minitest/spec"
require "minitest/autorun"

# Add '../lib' to the require path.
$: << File.join(File.dirname(__FILE__), "..", "lib")

glob = File.join(File.dirname(__FILE__), "ftw", "**", "*.rb")
Dir.glob(glob).each do |path|
  puts "Loading tests from #{path}"
  require File.expand_path(path)
end
