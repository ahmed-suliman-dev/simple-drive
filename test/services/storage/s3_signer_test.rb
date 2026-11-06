require "test_helper"

# Uses the worked examples from the AWS documentation, so the signer is checked
# against Amazon's own expected signatures:
# https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
class Storage::S3SignerTest < ActiveSupport::TestCase
  setup do
    @signer = Storage::S3Signer.new(
      access_key_id: "AKIAIOSFODNN7EXAMPLE",
      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      region: "us-east-1"
    )
    @time = Time.utc(2013, 5, 24)
  end

  test "matches the AWS example for GET Object" do
    headers = @signer.sign(
      method: "GET",
      uri: "https://examplebucket.s3.amazonaws.com/test.txt",
      payload_sha256: Storage::S3Signer::EMPTY_PAYLOAD_SHA256,
      headers: { "Range" => "bytes=0-9" },
      time: @time
    )

    assert_equal "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, " \
                 "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, " \
                 "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41",
                 headers["authorization"]
  end

  test "matches the AWS example for PUT Object" do
    body = "Welcome to Amazon S3."
    headers = @signer.sign(
      method: "PUT",
      uri: "https://examplebucket.s3.amazonaws.com/test%24file.text",
      payload_sha256: Digest::SHA256.hexdigest(body),
      headers: { "Date" => "Fri, 24 May 2013 00:00:00 GMT", "x-amz-storage-class" => "REDUCED_REDUNDANCY" },
      time: @time
    )

    assert headers["authorization"].end_with?(
      "Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd"
    )
  end

  test "adds the required x-amz headers" do
    headers = @signer.sign(method: "GET", uri: "http://localhost:9000/b/k",
                           payload_sha256: Storage::S3Signer::EMPTY_PAYLOAD_SHA256, time: @time)

    assert_equal "localhost:9000", headers["host"]
    assert_equal "20130524T000000Z", headers["x-amz-date"]
    assert_equal Storage::S3Signer::EMPTY_PAYLOAD_SHA256, headers["x-amz-content-sha256"]
  end

  test "leaves the default port out of the host header" do
    headers = @signer.sign(method: "GET", uri: "https://s3.amazonaws.com/b/k",
                           payload_sha256: Storage::S3Signer::EMPTY_PAYLOAD_SHA256, time: @time)

    assert_equal "s3.amazonaws.com", headers["host"]
  end
end
