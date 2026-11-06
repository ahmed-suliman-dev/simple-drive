require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "generate! returns a random token and stores only its digest" do
    record, token = ApiToken.generate!(name: "laptop")

    assert_match(/\A\h{64}\z/, token)
    assert_equal Digest::SHA256.hexdigest(token), record.token_digest
    assert_not_equal token, record.token_digest
  end

  test "authenticate finds the token by its plain value" do
    record, token = ApiToken.generate!(name: "laptop")

    assert_equal record, ApiToken.authenticate(token)
    assert_nil ApiToken.authenticate("wrong")
    assert_nil ApiToken.authenticate(nil)
  end
end
