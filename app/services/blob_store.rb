# Coordinates the metadata table with the storage backends.
#
# Controllers talk only to this class; they never know which backend is in use.
class BlobStore
  class DuplicateBlob < StandardError; end
  class BlobNotFound < StandardError; end

  # backend: lets tests inject a backend object instead of building one by name.
  def initialize(backend_name: Storage.default_backend_name, backend: nil)
    @backend_name = backend_name.to_s
    @backend = backend
  end

  # Stores the bytes and records their metadata. Returns the Blob record.
  #
  # The metadata row is inserted first, inside a transaction. The unique index
  # on blob_id makes a duplicate id fail before any bytes are written, so an
  # existing blob is never overwritten. If the backend then fails, the
  # transaction rolls back and no metadata points at missing data.
  def store(blob_id, data)
    backend = @backend || Storage.for(@backend_name)

    Blob.transaction do
      blob = Blob.create!(blob_id: blob_id, size: data.bytesize, storage_backend: @backend_name)
      backend.store(blob_id, data)
      blob
    end
  rescue ActiveRecord::RecordNotUnique
    raise DuplicateBlob
  rescue ActiveRecord::RecordInvalid => e
    raise DuplicateBlob if e.record.errors.of_kind?(:blob_id, :taken)

    raise
  end

  # Returns [blob, data]. Reads from the backend that stored the blob, which
  # may differ from the current default.
  def retrieve(blob_id)
    blob = Blob.find_by(blob_id: blob_id)
    raise BlobNotFound if blob.nil?

    data = Storage.for(blob.storage_backend).retrieve(blob_id)
    [blob, data]
  end
end
