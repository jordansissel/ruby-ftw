require "ftw/namespace"

# Provide resolution name -> address mappings through hash lookups
class FTW::DNS::Hash
  private

  # A new hash dns resolver.
  #
  # @param [#[]] data Must be a hash-like thing responding to #[]
  def initialize(data={})
    @data = data
  end # def initialize

  # Resolve a hostname.
  #
  # It will return an array of all known addresses for the host.
  def resolve(hostname)
    result = @data[hostname]
    return nil if result.nil?
    return result if result.is_a?(Array)
    return [result]
  end # def resolve

  public(:resolve)
end
