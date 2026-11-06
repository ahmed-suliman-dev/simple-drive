source "https://rubygems.org"

ruby ">= 3.2.0"

gem "rails", "~> 8.0.0"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 6.0"

# FTP storage backend (net-ftp was moved out of Ruby's default gems).
gem "net-ftp"

# Loads configuration from a .env file in development and test.
gem "dotenv-rails", groups: %i[development test]

# Windows does not ship zoneinfo files.
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  # Rails 8.0's test runner is built for Minitest 5.
  gem "minitest", "~> 5.25"
end

group :test do
  # Stubs HTTP calls so the S3 backend can be tested without a real server.
  gem "webmock"
end
