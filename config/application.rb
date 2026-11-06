require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module SimpleDrive
  class Application < Rails::Application
    config.load_defaults 8.0

    config.autoload_lib(ignore: %w[tasks])

    # JSON API only: no views, cookies, sessions or asset pipeline.
    config.api_only = true

    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc
  end
end
