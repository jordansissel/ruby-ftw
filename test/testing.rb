require "rubygems"
require "minitest/spec"
require "minitest/autorun"

# Add '../lib' to the require path.
$: << File.join(File.dirname(__FILE__), "..", "lib")

# I don't really like monkeypatching, but whatever, this is probably better
# than overriding the 'describe' method.
class MiniTest::Spec
  class << self
    # 'it' sounds wrong, call it 'test'
    alias :test :it
  end
end

if __FILE__ == $0
  glob = File.join(File.dirname(__FILE__), "net", "**", "*.rb")
  Dir.glob(glob).each do |path|
    puts "Loading tests from #{path}"
    require File.expand_path(path)
  end
end
