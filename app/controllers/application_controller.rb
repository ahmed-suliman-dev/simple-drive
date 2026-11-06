class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate!

  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render_error :bad_request, "invalid_json", "Request body must be valid JSON"
  end

  # Rails checks rescue_from handlers from the bottom up, so the more specific
  # ConfigurationError (a subclass of Storage::Error) must come after it.
  rescue_from Storage::Error do |error|
    Rails.logger.error("[storage] #{error.class}: #{error.message}")
    render_error :bad_gateway, "storage_error", "The storage backend failed to complete the request"
  end

  rescue_from Storage::ConfigurationError do |error|
    Rails.logger.error("[storage] configuration error: #{error.message}")
    render_error :internal_server_error, "storage_misconfigured", "The storage backend is not configured correctly"
  end

  private

  # Accepts "Authorization: Bearer <token>".
  def authenticate!
    authenticate_or_request_with_http_token do |token, _options|
      ApiToken.authenticate(token)
    end
  end

  # Called by authenticate_or_request_with_http_token when the token is
  # missing or wrong. Overridden to answer with JSON instead of plain text.
  def request_http_token_authentication(realm = "Application", _message = nil)
    headers["WWW-Authenticate"] = %(Bearer realm="#{realm.delete('"')}")
    render_error :unauthorized, "unauthorized", "A valid Bearer token is required"
  end

  def render_error(status, code, message)
    render json: { error: code, message: message }, status: status
  end
end
