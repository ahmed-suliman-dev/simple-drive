# Keep blob contents and secrets out of the logs.
Rails.application.config.filter_parameters += [:data, :token, :password, :secret]
