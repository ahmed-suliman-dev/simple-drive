require "digest"
require "securerandom"

# A Bearer token allowed to call the API.
#
# The plain token is shown exactly once, when it is generated. Only its
# SHA-256 digest is stored, and requests are matched by digest.
class ApiToken < ApplicationRecord
  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  # Creates a token and returns [record, plain_token].
  def self.generate!(name:)
    plain_token = SecureRandom.hex(32)
    record = create!(name: name, token_digest: digest(plain_token))
    [record, plain_token]
  end

  # Returns the matching token record, or nil.
  def self.authenticate(plain_token)
    return nil if plain_token.blank?

    token = find_by(token_digest: digest(plain_token))
    token&.touch(:last_used_at)
    token
  end

  def self.digest(plain_token)
    Digest::SHA256.hexdigest(plain_token)
  end
end
