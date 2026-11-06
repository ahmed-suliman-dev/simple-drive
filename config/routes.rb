Rails.application.routes.draw do
  namespace :v1, defaults: { format: :json } do
    post "blobs", to: "blobs#create"

    # A glob segment lets ids contain slashes (e.g. "photos/2024/cat.png").
    # format: false keeps dots in the id instead of treating them as a format.
    get "blobs/*id", to: "blobs#show", as: :blob, format: false
  end

  get "up", to: proc { [200, { "content-type" => "text/plain" }, ["OK"]] }
end
