# Raw blob bytes, used only by Storage::DatabaseBackend.
class BlobContent < ApplicationRecord
  validates :blob_id, presence: true, uniqueness: true
end
