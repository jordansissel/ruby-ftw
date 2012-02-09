require "ftw/namespace"

# Based on behavior and things described in RFC6265
class FTW::Cookies
  class Cookie
    # I could use stdlib CGI::Cookie, but it actually parses cookie strings
    # incorrectly and also lacks the 'httponly' attribute
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
    
    def initialize(name, value=nil, attributes={})
      @name = name
      @value = value
      
      [:domain, :path, :comment, :expires, :secure, :httponly].each do |iv|
        instance_variable_set("@#{iv.to_s}", attributes.delete(iv))
      end

      if !attributes.empty?
        raise InvalidArgument.new("Invalid Cookie attributes: #{attributes.inspect}")
      end
    end # def initialize

    # See RFC6265 section 4.1.1
    def self.parse(set_cookie_string)
      # TODO(sissel): Implement
    end
  end # class Cookie

  def initialize
    @cookies = []
  end # def initialize

  def add(name, value=nil, attributes={})
    cookie = Cookie.new(name, value, attributes)
    @cookies << cookie
  end # def add

  def add_from_header(set_cookie_string)
    cookie = Cookie.parse(set_cookie_string)
    @cookies << cookie
  end # def add_from_header

  def for_url(url)
    # TODO(sissel): only return cookies that are valid for the url
    return @cookies
  end # def for_url
end # class FTW::Cookies
