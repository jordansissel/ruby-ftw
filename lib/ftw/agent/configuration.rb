require "ftw"

# Experimentation with an agent configuration similar to Firefox's about:config
module FTW::Agent::Configuration
  # The config key for setting how many redirects will be followed before
  # giving up.
  REDIRECTION_LIMIT = "redirection-limit".freeze

  # Get the configuration hash
  def configuration
    return @configuration ||= Hash.new
  end # def configuration
end # def FTW::Agent::Configuration
