require "ftw"

module FTW::Agent::Configuration
  REDIRECTION_LIMIT = "redirection-limit".freeze

  def configuration
    return @configuration ||= Hash.new
  end
end
