require "net/ftw/namespace"
require "ftw/crlf"

# HTTP Headers
#
# See RFC2616 section 4.2: <http://tools.ietf.org/html/rfc2616#section-4.2>
#
# Section 14.44 says Field Names in the header are case-insensitive, so
# this library always forces field names to be lowercase. This includes
# get() calls.
#
#    headers.set("HELLO", "world")
#    headers.get("hello")   # ===> "world"
#
class FTW::HTTP::Headers
  include Enumerable
  include FTW::CRLF

  # Make a new headers container. You can pass a hash of 
  public
  def initialize(headers={})
    super()
    @version = 1.1
    @headers = headers
  end # def initialize

  # Set a header field to a specific value.
  # Any existing value(s) for this field are destroyed.
  def set(field, value)
    @headers[field.downcase] = value
  end # def set

  # Set a header field to a specific value.
  # Any existing value(s) for this field are destroyed.
  def include?(field)
    @headers.include?(field.downcase)
  end # def include?

  # Add a header field with a value.
  #
  # If this field already exists, another value is added.
  # If this field does not already exist, it is set.
  def add(field, value)
    field = field.downcase
    if @headers.include?(field)
      if @headers[field].is_a?(Array)
        @headers[field] << value
      else
        @headers[field] = [@headers[field], value]
      end
    else
      set(field, value)
    end
  end # def add

  # Removes a header entry. If the header has multiple values
  # (like X-Forwarded-For can), you can delete a specific entry
  # by passing the value of the header field to remove.
  #
  #     # Remove all X-Forwarded-For entries
  #     headers.remove("X-Forwarded-For") 
  #     # Remove a specific X-Forwarded-For entry
  #     headers.remove("X-Forwarded-For", "1.2.3.4")
  #
  # * If you remove a field that doesn't exist, no error will occur.
  # * If you remove a field value that doesn't exist, no error will occur.
  # * If you remove a field value that is the only value, it is the same as
  #   removing that field by name.
  def remove(field, value=nil)
    field = field.downcase
    if value.nil?
      # no value, given, remove the entire field.
      @headers.delete(field)
    else
      field_value = @headers[field]
      if field_value.is_a?(Array)
        # remove a specific value
        field_value.delete(value)
        # Down to a String again if there's only one value.
        if field_value.size == 1
          set(field, field_value.first)
        end
      else
        # Remove this field if the value matches
        if field_value == value
          remove(field)
        end
      end
    end
  end # def remove

  # Get a field value. 
  # 
  # This will return:
  #   * String if there is only a single value for this field
  #   * Array of String if there are multiple values for this field
  def get(field)
    field = field.downcase
    return @headers[field]
  end # def get

  # Iterate over headers. Given to the block are two arguments, the field name
  # and the field value. For fields with multiple values, you will receive
  # that same field name multiple times, like:
  #    yield "Host", "www.example.com"
  #    yield "X-Forwarded-For", "1.2.3.4"
  #    yield "X-Forwarded-For", "1.2.3.5"
  def each(&block)
    @headers.each do |field_name, field_value|
      if field_value.is_a?(Array)
        field_value.map { |value| yield field_name, v }
      else
        yield field_name, field_value
      end
    end
  end # end each

  public
  def to_s
    return @headers.collect { |name, value| "#{name}: #{value}" }.join(CRLF) + CRLF
  end # def to_s
end # class FTW::HTTP::Headers
