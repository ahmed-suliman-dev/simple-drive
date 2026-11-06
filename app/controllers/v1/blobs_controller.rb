require "base64"

module V1
  class BlobsController < ApplicationController
    # POST /v1/blobs
    # Body: { "id": "any-string", "data": "<base64>" }
    def create
      blob_id = params[:id]
      encoded = params[:data]

      unless blob_id.is_a?(String) && blob_id.present?
        return render_error(:unprocessable_entity, "invalid_id", "id must be a non-empty string")
      end

      if blob_id.length > 1024
        return render_error(:unprocessable_entity, "invalid_id", "id must be at most 1024 characters")
      end

      unless encoded.is_a?(String) && encoded.present?
        return render_error(:unprocessable_entity, "invalid_data", "data must be a non-empty Base64 string")
      end

      data = decode_base64(encoded)
      if data.nil?
        return render_error(:unprocessable_entity, "invalid_data", "data is not valid Base64")
      end

      blob = BlobStore.new.store(blob_id, data)
      render json: metadata_json(blob), status: :created
    rescue BlobStore::DuplicateBlob
      render_error :conflict, "duplicate_id", "A blob with this id already exists"
    end

    # GET /v1/blobs/:id
    def show
      blob, data = BlobStore.new.retrieve(params[:id])
      render json: metadata_json(blob).merge(data: Base64.strict_encode64(data))
    rescue BlobStore::BlobNotFound
      render_error :not_found, "not_found", "No blob exists with this id"
    end

    private

    # Strict decoding rejects anything that is not canonical Base64
    # (invalid characters, bad padding, embedded newlines).
    def decode_base64(encoded)
      Base64.strict_decode64(encoded)
    rescue ArgumentError
      nil
    end

    # Field order and types follow the brief's example response.
    def metadata_json(blob)
      {
        id: blob.blob_id,
        size: blob.size.to_s,
        created_at: blob.created_at.utc.iso8601
      }
    end
  end
end
