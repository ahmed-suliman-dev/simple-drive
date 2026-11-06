module Storage
  # Stores bytes in the blob_contents table, separate from the blobs metadata table.
  class DatabaseBackend < Base
    def store(blob_id, data)
      BlobContent.create!(blob_id: blob_id, data: data)
    rescue ActiveRecord::ActiveRecordError => e
      raise Error, "database backend failed to store blob: #{e.message}"
    end

    def retrieve(blob_id)
      content = BlobContent.find_by(blob_id: blob_id)
      raise NotFound, "blob not found in database backend" if content.nil?

      content.data.b
    end
  end
end
