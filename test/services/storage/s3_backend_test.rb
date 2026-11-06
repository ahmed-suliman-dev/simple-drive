require "test_helper"

class Storage::S3BackendTest < ActiveSupport::TestCase
  setup do
    @backend = Storage::S3Backend.new(
      endpoint: "http://minio.test:9000", bucket: "simple-drive", region: "us-east-1",
      access_key_id: "minioadmin", secret_access_key: "minioadmin"
    )
    @key_url = "http://minio.test:9000/simple-drive/blobs/#{Digest::SHA256.hexdigest('photo.png')}"
  end

  test "store sends a signed PUT with the raw bytes" do
    data = "\x00\xFFbinary".b
    stub_request(:put, @key_url).to_return(status: 200)

    @backend.store("photo.png", data)

    assert_requested(:put, @key_url) do |request|
      request.body == data &&
        request.headers["X-Amz-Content-Sha256"] == Digest::SHA256.hexdigest(data) &&
        request.headers["X-Amz-Date"].match?(/\A\d{8}T\d{6}Z\z/) &&
        request.headers["Authorization"].match?(
          %r{\AAWS4-HMAC-SHA256 Credential=minioadmin/\d{8}/us-east-1/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=\h{64}\z}
        )
    end
  end

  test "retrieve returns the object body as binary" do
    stub_request(:get, @key_url).to_return(status: 200, body: "hello")

    data = @backend.retrieve("photo.png")

    assert_equal "hello", data
    assert_equal Encoding::BINARY, data.encoding
  end

  test "retrieve raises NotFound on 404" do
    stub_request(:get, @key_url).to_return(status: 404, body: "<Error><Code>NoSuchKey</Code></Error>")

    assert_raises(Storage::NotFound) { @backend.retrieve("photo.png") }
  end

  test "includes the S3 error code when a request is rejected" do
    stub_request(:put, @key_url).to_return(
      status: 403,
      body: "<Error><Code>SignatureDoesNotMatch</Code><Message>bad signature</Message></Error>"
    )

    error = assert_raises(Storage::Error) { @backend.store("photo.png", "x") }
    assert_match "403 SignatureDoesNotMatch bad signature", error.message
  end

  test "wraps network failures in Storage::Error" do
    stub_request(:get, @key_url).to_raise(Errno::ECONNREFUSED)

    assert_raises(Storage::Error) { @backend.retrieve("photo.png") }
  end

  test "rejects an endpoint that is not an http url" do
    assert_raises(Storage::ConfigurationError) do
      Storage::S3Backend.new(endpoint: "minio:9000", bucket: "b", region: "r", access_key_id: "a", secret_access_key: "s")
    end
  end
end
