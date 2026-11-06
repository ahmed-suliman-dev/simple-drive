require "test_helper"

class BlobsApiTest < ActionDispatch::IntegrationTest
  # Example from the brief: "Hello Simple Storage World!" is 27 bytes.
  ID = "any_valid_string_or_identifier".freeze
  DATA = "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh".freeze

  def post_blob(id: ID, data: DATA, headers: auth_headers)
    post "/v1/blobs", params: { id: id, data: data }.to_json, headers: headers
  end

  # --- Authentication ------------------------------------------------------

  test "rejects requests without a token" do
    post "/v1/blobs", params: { id: ID, data: DATA }.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
    assert_match(/\ABearer/, response.headers["WWW-Authenticate"])
  end

  test "rejects requests with a wrong token" do
    post_blob(headers: auth_headers("not-a-real-token"))
    assert_response :unauthorized

    get "/v1/blobs/#{ID}", headers: auth_headers("not-a-real-token")
    assert_response :unauthorized
  end

  test "records when a token was last used" do
    post_blob
    assert_not_nil ApiToken.find_by(name: "test").last_used_at
  end

  # --- Storing -------------------------------------------------------------

  test "stores a blob and returns its metadata" do
    with_env("STORAGE_BACKEND" => "database") { post_blob }

    assert_response :created
    body = response.parsed_body
    assert_equal ID, body["id"]
    assert_equal "27", body["size"]
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, body["created_at"])

    blob = Blob.find_by!(blob_id: ID)
    assert_equal "database", blob.storage_backend
    assert_equal "Hello Simple Storage World!", BlobContent.find_by!(blob_id: ID).data
  end

  test "rejects a duplicate id and keeps the original data" do
    post_blob
    post_blob(data: Base64.strict_encode64("something else"))

    assert_response :conflict
    assert_equal "duplicate_id", response.parsed_body["error"]

    get "/v1/blobs/#{ID}", headers: auth_headers
    assert_equal DATA, response.parsed_body["data"]
  end

  test "rejects data that is not valid Base64" do
    ["not base64!!", "SGVsbG8=extra", "SGVsbG8\nV29ybGQ="].each do |bad|
      post_blob(id: SecureRandom.uuid, data: bad)

      assert_response :unprocessable_entity, "expected #{bad.inspect} to be rejected"
      assert_equal "invalid_data", response.parsed_body["error"]
    end
    assert_equal 0, Blob.count
  end

  test "rejects a missing or non-string id" do
    [nil, "", 123, { "a" => 1 }].each do |bad|
      post_blob(id: bad)

      assert_response :unprocessable_entity
      assert_equal "invalid_id", response.parsed_body["error"]
    end
  end

  test "rejects missing data" do
    post_blob(data: nil)

    assert_response :unprocessable_entity
    assert_equal "invalid_data", response.parsed_body["error"]
  end

  test "rejects malformed JSON" do
    post "/v1/blobs", params: "{not json", headers: auth_headers

    assert_response :bad_request
    assert_equal "invalid_json", response.parsed_body["error"]
  end

  # --- Retrieving ----------------------------------------------------------

  test "retrieves a blob in the format from the brief" do
    post_blob
    get "/v1/blobs/#{ID}", headers: auth_headers

    assert_response :ok
    body = response.parsed_body
    assert_equal %w[id data size created_at].sort, body.keys.sort
    assert_equal ID, body["id"]
    assert_equal DATA, body["data"]
    assert_equal "27", body["size"]
  end

  test "returns 404 for an unknown id" do
    get "/v1/blobs/missing", headers: auth_headers

    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]
  end

  test "supports ids that look like paths, contain dots or are UUIDs" do
    ["photos/2024/cat.png", "report.final.pdf", SecureRandom.uuid].each do |id|
      post_blob(id: id)
      assert_response :created

      get "/v1/blobs/#{id}", headers: auth_headers
      assert_response :ok
      assert_equal id, response.parsed_body["id"]
    end
  end

  test "round-trips arbitrary binary data byte for byte" do
    bytes = (0..255).map(&:chr).join.b
    post_blob(id: "binary", data: Base64.strict_encode64(bytes))

    get "/v1/blobs/binary", headers: auth_headers
    assert_equal bytes, Base64.strict_decode64(response.parsed_body["data"])
    assert_equal "256", response.parsed_body["size"]
  end

  # --- Backends ------------------------------------------------------------

  test "stores and retrieves through the local file system backend" do
    Dir.mktmpdir do |dir|
      with_env("STORAGE_BACKEND" => "local", "LOCAL_STORAGE_PATH" => dir) do
        post_blob
        assert_response :created

        get "/v1/blobs/#{ID}", headers: auth_headers
        assert_equal DATA, response.parsed_body["data"]
      end

      assert_equal "local", Blob.find_by!(blob_id: ID).storage_backend
      assert_equal 0, BlobContent.count
    end
  end

  test "reads old blobs from the backend that stored them after the default changes" do
    with_env("STORAGE_BACKEND" => "database") { post_blob }

    Dir.mktmpdir do |dir|
      with_env("STORAGE_BACKEND" => "local", "LOCAL_STORAGE_PATH" => dir) do
        get "/v1/blobs/#{ID}", headers: auth_headers
        assert_response :ok
        assert_equal DATA, response.parsed_body["data"]
      end
    end
  end

  test "stores through the S3 backend" do
    stored = {}
    stub_request(:put, %r{\Ahttp://minio.test:9000/simple-drive/blobs/})
      .to_return { |request| stored[request.uri.path] = request.body; { status: 200 } }
    stub_request(:get, %r{\Ahttp://minio.test:9000/simple-drive/blobs/})
      .to_return { |request| { status: 200, body: stored.fetch(request.uri.path) } }

    s3_env = {
      "STORAGE_BACKEND" => "s3", "S3_ENDPOINT" => "http://minio.test:9000", "S3_BUCKET" => "simple-drive",
      "S3_ACCESS_KEY_ID" => "key", "S3_SECRET_ACCESS_KEY" => "secret"
    }
    with_env(s3_env) do
      post_blob
      assert_response :created

      get "/v1/blobs/#{ID}", headers: auth_headers
      assert_equal DATA, response.parsed_body["data"]
    end
  end

  test "returns 502 and stores no metadata when the backend fails" do
    stub_request(:put, /minio.test/).to_return(status: 500, body: "<Error><Code>InternalError</Code></Error>")

    s3_env = {
      "STORAGE_BACKEND" => "s3", "S3_ENDPOINT" => "http://minio.test:9000", "S3_BUCKET" => "b",
      "S3_ACCESS_KEY_ID" => "key", "S3_SECRET_ACCESS_KEY" => "secret"
    }
    with_env(s3_env) { post_blob }

    assert_response :bad_gateway
    assert_equal "storage_error", response.parsed_body["error"]
    assert_equal 0, Blob.count
  end

  test "returns 500 when the configured backend is unknown" do
    with_env("STORAGE_BACKEND" => "floppy-disk") { post_blob }

    assert_response :internal_server_error
    assert_equal "storage_misconfigured", response.parsed_body["error"]
  end
end
