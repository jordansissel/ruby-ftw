require "ftw/namespace"

# This module provides a 'CRLF' constant for use with protocols that need it.
# I find it easier to specify CRLF instead of literal "\r\n"
module FTW::CRLF
  # carriage-return + line-feed
  CRLF = "\r\n"
end # module FTW::CRLF
