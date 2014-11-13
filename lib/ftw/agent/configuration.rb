require "ftw"

# Experimentation with an agent configuration similar to Firefox's about:config
module FTW::Agent::Configuration
  # The config key for setting how many redirects will be followed before
  # giving up.
  REDIRECTION_LIMIT = "redirection-limit".freeze

  # SSL Trust Store
  SSL_TRUST_STORE = "ssl.trustdb".freeze

  # SSL: Use the system's global default certs?
  SSL_USE_DEFAULT_CERTS = "ssl.use-default-certs".freeze

  # SSL cipher strings
  SSL_CIPHERS = "ssl.ciphers".freeze

  SSL_CIPHER_MAP = {
    # https://wiki.mozilla.org/Security/Server_Side_TLS
    "MOZILLA_MODERN" => "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK",
    "MOZILLA_INTERMEDIATE" => "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA",
    "MOZILLA_OLD" => "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA"
  }

  SSL_CIPHER_DEFAULT_MRI = SSL_CIPHER_MAP["MOZILLA_INTERMEDIATE"]

  # For whatever reason, I can't figure out how to correctly set desired cipher suites under JRuby
  # Something is funky with OpenSSL::SSL::SSLContext#ciphers= and I dont' know what.
  # Details:
  #   - https://github.com/jruby/jruby/issues/2194
  #   - https://github.com/jruby/jruby/issues/2193
  #   - https://gist.github.com/jordansissel/8e4d6786638ead737cb5
  #
  # So we'll have to rely on whatever BouncyCastle(?) determines to be the best defaults.
  #
  # At time of writing, the "HIGH" cipher suite includes:
  # (according to wireshark showing the TLS Client Hello)
  # Cipher Suites (8 suites)
  #   Cipher Suite: TLS_DHE_DSS_WITH_3DES_EDE_CBC_SHA (0x0013)
  #   Cipher Suite: TLS_DHE_DSS_WITH_AES_128_CBC_SHA (0x0032)
  #   Cipher Suite: TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA (0x0016)
  #   Cipher Suite: TLS_DHE_RSA_WITH_AES_128_CBC_SHA (0x0033)
  #   Cipher Suite: TLS_DH_anon_WITH_3DES_EDE_CBC_SHA (0x001b)
  #   Cipher Suite: TLS_DH_anon_WITH_AES_128_CBC_SHA (0x0034)
  #   Cipher Suite: TLS_RSA_WITH_3DES_EDE_CBC_SHA (0x000a)
  #   Cipher Suite: TLS_RSA_WITH_AES_128_CBC_SHA (0x002f)
  SSL_CIPHER_DEFAULT_JAVA = "HIGH"

  if RUBY_ENGINE == "java"
    SSL_CIPHER_DEFAULT = SSL_CIPHER_DEFAULT_JAVA
  else
    SSL_CIPHER_DEFAULT = SSL_CIPHER_DEFAULT_MRI
  end

  SSL_VERSION = "ssl.version"

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
      SSL_TRUST_STORE => File.join(home, "ssl-trust.db"),
      SSL_USE_DEFAULT_CERTS => true,
      SSL_CIPHERS => SSL_CIPHER_DEFAULT,
      SSL_VERSION => "TLSv1.1",
    }
  end # def default_configuration

  def tmpdir
    return File.join(Dir.tmpdir, "ftw-#{Process.uid}")
  end # def tmpdir

  public(:configuration)
end # def FTW::Agent::Configuration
