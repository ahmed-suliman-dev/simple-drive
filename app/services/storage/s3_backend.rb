require "net/http"
require "uri"
require "digest"

module Storage
  # Talks to any S3-compatible service (AWS S3, MinIO, DigitalOcean Spaces,
  # Linode Object Storage) using only Net::HTTP and our own SigV4 signer.
  #
  # Uses path-style URLs (<endpoint>/<bucket>/<key>), which every
  # S3-compatible service supports and which work with plain local hosts.
  class S3Backend < Base
    KEY_PREFIX = "blobs/".freeze

    def initialize(endpoint:, bucket:, region:, access_key_id:, secret_access_key:, open_timeout: 5, read_timeout: 30)
      super()
      @endpoint = URI(endpoint.to_s.chomp("/"))
      unless @endpoint.is_a?(URI::HTTP) && @endpoint.host
        raise ConfigurationError, "S3_ENDPOINT must be an http(s) URL, got #{endpoint.inspect}"
      end

      @bucket = bucket
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @signer = S3Signer.new(access_key_id: access_key_id, secret_access_key: secret_access_key, region: region)
    end

    # PUT /<bucket>/<key>
    def store(blob_id, data)
      uri = object_uri(blob_id)
      request = Net::HTTP::Put.new(uri)
      request.body = data
      sign!(request, uri, Digest::SHA256.hexdigest(data), "content-type" => "application/octet-stream")

      response = perform(uri, request)
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "S3 PUT failed: #{describe(response)}"
    end

    # GET /<bucket>/<key>
    def retrieve(blob_id)
      uri = object_uri(blob_id)
      request = Net::HTTP::Get.new(uri)
      # Ask for the bytes exactly as stored.
      request["accept-encoding"] = "identity"
      sign!(request, uri, S3Signer::EMPTY_PAYLOAD_SHA256)

      response = perform(uri, request)
      case response
      when Net::HTTPSuccess then response.body.to_s.b
      when Net::HTTPNotFound then raise NotFound, "blob not found in S3 backend"
      else raise Error, "S3 GET failed: #{describe(response)}"
      end
    end

    private

    def object_uri(blob_id)
      URI("#{@endpoint}/#{@bucket}/#{KEY_PREFIX}#{object_name(blob_id)}")
    end

    def sign!(request, uri, payload_sha256, extra_headers = {})
      @signer.sign(method: request.method, uri: uri, payload_sha256: payload_sha256, headers: extra_headers)
             .each { |name, value| request[name] = value }
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      open_timeout: @open_timeout,
                      read_timeout: @read_timeout) do |http|
        http.request(request)
      end
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise Error, "could not reach S3 endpoint #{@endpoint}: #{e.class}: #{e.message}"
    end

    # S3 errors come back as XML: <Error><Code>...</Code><Message>...</Message></Error>
    def describe(response)
      body = response.body.to_s
      code = body[%r{<Code>(.*?)</Code>}m, 1]
      message = body[%r{<Message>(.*?)</Message>}m, 1]
      [response.code, code, message].compact.join(" ")
    end
  end
end
