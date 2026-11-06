ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "tmpdir"

# Tests must not depend on the developer's .env file. Each test that needs
# another backend sets it explicitly with with_env.
ENV["STORAGE_BACKEND"] = "database"

module EnvHelper
  # Temporarily sets environment variables for the duration of the block.
  def with_env(vars)
    previous = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end

module ActiveSupport
  class TestCase
    # Tests change ENV, so run them in a single process.
    parallelize(workers: 1)

    include EnvHelper
  end
end

class ActionDispatch::IntegrationTest
  include EnvHelper

  setup do
    _record, @token = ApiToken.generate!(name: "test")
  end

  def auth_headers(token = @token)
    { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end
end
