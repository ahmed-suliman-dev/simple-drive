Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exceptions as error responses instead of raising them.
  config.action_dispatch.show_exceptions = :rescuable

  config.active_support.deprecation = :stderr
end
