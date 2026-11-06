# Storage backends share one interface (see Storage::Base):
#
#   store(blob_id, data)  -> writes bytes
#   retrieve(blob_id)     -> returns bytes, or raises Storage::NotFound
#
# Storage.for(name) builds a backend from environment variables, so the
# backend is chosen by configuration, not by code.
module Storage
  class Error < StandardError; end
  class NotFound < Error; end
  class ConfigurationError < Error; end

  BACKENDS = %w[database local s3 ftp].freeze

  def self.default_backend_name
    ENV.fetch("STORAGE_BACKEND", "database")
  end

  def self.for(name)
    case name.to_s
    when "database"
      DatabaseBackend.new
    when "local"
      LocalBackend.new(root: required_env("LOCAL_STORAGE_PATH"))
    when "s3"
      S3Backend.new(
        endpoint: required_env("S3_ENDPOINT"),
        bucket: required_env("S3_BUCKET"),
        region: ENV.fetch("S3_REGION", "us-east-1"),
        access_key_id: required_env("S3_ACCESS_KEY_ID"),
        secret_access_key: required_env("S3_SECRET_ACCESS_KEY")
      )
    when "ftp"
      FtpBackend.new(
        host: required_env("FTP_HOST"),
        port: Integer(ENV.fetch("FTP_PORT", "21")),
        username: required_env("FTP_USERNAME"),
        password: required_env("FTP_PASSWORD"),
        directory: ENV.fetch("FTP_DIRECTORY", "simple-drive"),
        passive: ENV.fetch("FTP_PASSIVE", "true") != "false"
      )
    else
      raise ConfigurationError, "Unknown storage backend #{name.inspect}; expected one of #{BACKENDS.join(', ')}"
    end
  end

  def self.required_env(key)
    value = ENV[key]
    raise ConfigurationError, "#{key} must be set" if value.nil? || value.strip.empty?

    value
  end
end
