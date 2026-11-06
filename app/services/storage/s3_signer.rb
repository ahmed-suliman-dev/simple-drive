require "openssl"
require "digest"
require "uri"

module Storage
  # Hand-written AWS Signature Version 4 for S3. The brief forbids S3 libraries.
  #
  # Reference: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
  #
  # Signing has four steps:
  #   1. Canonical request: method, path, query, headers and payload hash in a fixed format.
  #   2. String to sign: algorithm, timestamp, credential scope, and the SHA-256 of step 1.
  #   3. Signing key: the secret key HMAC-chained with date, region, service and "aws4_request".
  #   4. Signature: HMAC-SHA256 of step 2 with the key from step 3, sent in the Authorization header.
  class S3Signer
    ALGORITHM = "AWS4-HMAC-SHA256".freeze
    SERVICE = "s3".freeze
    EMPTY_PAYLOAD_SHA256 = Digest::SHA256.hexdigest("").freeze

    def initialize(access_key_id:, secret_access_key:, region:)
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
      @region = region
    end

    # Returns the headers to send: the given headers plus host, x-amz-date,
    # x-amz-content-sha256 and authorization. All names are lowercase.
    def sign(method:, uri:, payload_sha256:, headers: {}, time: Time.now.utc)
      uri = URI(uri)
      time = time.utc
      amz_date = time.strftime("%Y%m%dT%H%M%SZ")
      date = time.strftime("%Y%m%d")

      signed = headers.to_h { |name, value| [name.to_s.downcase, value.to_s] }
      signed["host"] = host_header(uri)
      signed["x-amz-date"] = amz_date
      signed["x-amz-content-sha256"] = payload_sha256

      names = signed.keys.sort
      signed_headers = names.join(";")
      canonical_headers = names.map { |name| "#{name}:#{normalize(signed[name])}\n" }.join

      request = canonical_request(method, uri, canonical_headers, signed_headers, payload_sha256)
      scope = "#{date}/#{@region}/#{SERVICE}/aws4_request"
      to_sign = [ALGORITHM, amz_date, scope, sha256_hex(request)].join("\n")
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key(date), to_sign)

      signed.merge(
        "authorization" => "#{ALGORITHM} Credential=#{@access_key_id}/#{scope}, " \
                           "SignedHeaders=#{signed_headers}, Signature=#{signature}"
      )
    end

    private

    def canonical_request(method, uri, canonical_headers, signed_headers, payload_sha256)
      [
        method.to_s.upcase,
        uri.path.empty? ? "/" : uri.path,
        canonical_query(uri.query),
        canonical_headers,
        signed_headers,
        payload_sha256
      ].join("\n")
    end

    # Query parameters sorted by name, each name and value URI-encoded.
    def canonical_query(query)
      return "" if query.nil? || query.empty?

      query.split("&").map do |pair|
        name, value = pair.split("=", 2)
        [uri_encode(URI.decode_www_form_component(name)), uri_encode(URI.decode_www_form_component(value.to_s))]
      end.sort.map { |name, value| "#{name}=#{value}" }.join("&")
    end

    # AWS encoding: everything except A-Z a-z 0-9 - _ . ~ becomes %XX (uppercase hex).
    def uri_encode(value)
      value.to_s.b.gsub(/[^A-Za-z0-9\-_.~]/n) { |char| format("%%%02X", char.ord) }
    end

    # Default ports are left out of the Host header, as HTTP clients do.
    def host_header(uri)
      default_port = uri.scheme == "https" ? 443 : 80
      uri.port == default_port ? uri.host : "#{uri.host}:#{uri.port}"
    end

    # Trim and collapse runs of spaces, as SigV4 requires.
    def normalize(value)
      value.strip.gsub(/\s+/, " ")
    end

    def signing_key(date)
      k_date = hmac("AWS4#{@secret_access_key}", date)
      k_region = hmac(k_date, @region)
      k_service = hmac(k_region, SERVICE)
      hmac(k_service, "aws4_request")
    end

    def hmac(key, data)
      OpenSSL::HMAC.digest("SHA256", key, data)
    end

    def sha256_hex(data)
      Digest::SHA256.hexdigest(data)
    end
  end
end
