require "ftw"

# Experimentation with an agent configuration similar to Firefox's about:config
module FTW::Agent::Configuration
  # The config key for setting how many redirects will be followed before
  # giving up.
  REDIRECTION_LIMIT = "redirection-limit".freeze

  # SSL Trust Store
  SSL_TRUST_STORE = "ssl.trustdb".freeze

  private

  # Get the configuration hash
  def configuration
    return @configuration ||= default_configuration
  end # def configuration

  # default configuration
  def default_configuration
    require "tmpdir"
    home = File.join(ENV.fetch("HOME", tmpdir), ".ftw")
    return {
      REDIRECTION_LIMIT => 20,
      SSL_TRUST_STORE => File.join(home, "ssl-trust.db")
    }
  end # def default_configuration

  def tmpdir
    return File.join(Dir.tmpdir, "ftw-#{Process.uid}")
  end # def tmpdir

  public(:configuration)
end # def FTW::Agent::Configuration
