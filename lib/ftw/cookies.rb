require "ftw/namespace"
require "cabin"

# Based on behavior and things described in RFC6265
class FTW::Cookies

  # This is a Cookie. It expires, has a value, a name, etc.
  # I could have used stdlib CGI::Cookie, but it actually parses cookie strings
  # incorrectly and also lacks the 'httponly' attribute.
  class Cookie
    attr_accessor :name
    attr_accessor :value

    attr_accessor :domain
    attr_accessor :path
    attr_accessor :comment
    attr_accessor :expires # covers both 'expires' and 'max-age' behavior
    attr_accessor :secure
    attr_accessor :httponly # part of RFC6265

    # TODO(sissel): Support 'extension-av' ? RFC6265 section 4.1.1
    # extension-av      = <any CHAR except CTLs or ";">
 
    # List of standard cookie attributes
    STANDARD_ATTRIBUTES = [:domain, :path, :comment, :expires, :secure, :httponly]

    # A new cookie. Value and attributes are optional.
    def initialize(name, value=nil, attributes={})
      @name = name
      @value = value
      
      STANDARD_ATTRIBUTES.each do |iv|
        instance_variable_set("@#{iv.to_s}", attributes.delete(iv))
      end

      if !attributes.empty?
        raise InvalidArgument.new("Invalid Cookie attributes: #{attributes.inspect}")
      end
    end # def initialize

    # See RFC6265 section 4.1.1
    def self.parse(set_cookie_string)
      @logger ||= Cabin::Channel.get($0)
      # TODO(sissel): Implement
      # grammar is:
      #  set-cookie-string = cookie-pair *( ";" SP cookie-av )
      #  cookie-pair       = cookie-name "=" cookie-value
      #  cookie-name       = token
      #  cookie-value      = *cookie-octet / ( DQUOTE *cookie-octet DQUOTE )
      pair, *attributes = set_cookie_string.split(/\s*;\s*/)
      name, value = pair.split(/\s*=\s*/)
      extra = {}
      attributes.each do |attr|
        case attr
          when /^Expires=/
            #extra[:expires] = 
          when /^Max-Age=/
            # TODO(sissel): Parse the Max-Age value and convert it to 'expires'
            #extra[:expires] = 
          when /^Domain=/
            extra[:domain] = attr[7..-1]
          when /^Path=/
            extra[:path] = attr[5..-1]
          when /^Secure/
            extra[:secure] = true
          when /^HttpOnly/
            extra[:httponly] = true
          else
            
        end
      end
    end # def Cookie.parse
  end # class Cookie

  # A new cookies store
  def initialize
    @cookies = []
  end # def initialize

  # Add a cookie 
  def add(name, value=nil, attributes={})
    cookie = Cookie.new(name, value, attributes)
    @cookies << cookie
  end # def add

  # Add a cookie from a header 'Set-Cookie' value
  def add_from_header(set_cookie_string)
    cookie = Cookie.parse(set_cookie_string)
    @cookies << cookie
  end # def add_from_header

  # Get cookies for a URL
  def for_url(url)
    # TODO(sissel): only return cookies that are valid for the url
    return @cookies
  end # def for_url
end # class FTW::Cookies
