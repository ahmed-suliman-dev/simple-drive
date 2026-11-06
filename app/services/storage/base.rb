require "digest"

module Storage
  # Abstract parent of every backend.
  class Base
    # Writes the bytes for blob_id.
    def store(blob_id, data)
      raise NotImplementedError, "#{self.class} must implement #store"
    end

    # Returns the bytes for blob_id (a binary String), or raises Storage::NotFound.
    def retrieve(blob_id)
      raise NotImplementedError, "#{self.class} must implement #retrieve"
    end

    private

    # Blob ids are arbitrary user text ("../../etc/passwd", spaces, unicode...).
    # Backends that use names (files, S3 keys, FTP paths) store each blob under
    # the SHA-256 of its id: always 64 safe hex characters, no path traversal,
    # no encoding edge cases. The metadata table keeps the original id.
    def object_name(blob_id)
      Digest::SHA256.hexdigest(blob_id)
    end
  end
end
