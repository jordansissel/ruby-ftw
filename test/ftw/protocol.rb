#require File.join(File.expand_path(__FILE__).sub(/\/ftw\/.*/, "/testing"))
require 'ftw/protocol'
require 'stringio'

describe FTW::Protocol do

  class OnlySysread < Struct.new(:io)
    def sysread(*args)
      io.sysread(*args)
    end
  end

  class OnlyRead < Struct.new(:io)
    def read(*args)
      io.read(*args)
    end
  end

  test "reading body via #read" do
    protocol = Object.new
    protocol.extend FTW::Protocol

    output = StringIO.new
    input  = OnlyRead.new( StringIO.new('Some example input') )

    protocol.write_http_body(input, output, false)

    output.rewind
    assert_equal( output.string, 'Some example input')
  end

  test "reading body via #sysread chunked" do
    protocol = Object.new
    protocol.extend FTW::Protocol

    output = StringIO.new
    input  = OnlySysread.new( StringIO.new('Some example input') )

    protocol.write_http_body(input, output, true)

    output.rewind
    assert_equal( output.string, "12\r\nSome example input\r\n0\r\n\r\n")
  end

  test "reading body via #read chunked" do
    protocol = Object.new
    protocol.extend FTW::Protocol

    output = StringIO.new
    input  = OnlyRead.new( StringIO.new('Some example input') )

    protocol.write_http_body(input, output, true)

    output.rewind
    assert_equal( output.string, "12\r\nSome example input\r\n0\r\n\r\n")
  end

  class OneByteWriter < Struct.new(:io)

    def write( str )
      io.write(str[0..1])
    end

  end

  test "writing partially" do
    protocol = Object.new
    protocol.extend FTW::Protocol

    output = OneByteWriter.new( StringIO.new )
    input  = OnlyRead.new( StringIO.new('Some example input') )

    protocol.write_http_body(input, output, true)

    output.io.rewind
    assert_equal( output.io.string, "12\r\nSome example input\r\n0\r\n\r\n")
  end

  test "writing non ascii characters" do
    protocol = Object.new
    protocol.extend FTW::Protocol

    output = StringIO.new
    input  = "è".force_encoding(Encoding::UTF_8)

    protocol.write_http_body(input, output, true)

    output.rewind
    assert_equal( output.string, "2\r\nè\r\n0\r\n\r\n")
  end

end
