# Metadata for a stored blob: its id, size, which backend holds it, and when
# it was created. Remembering the backend per blob means blobs stay readable
# even after an administrator switches the default backend.
class Blob < ApplicationRecord
  validates :blob_id, presence: true, uniqueness: true, length: { maximum: 1024 }
  validates :size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :storage_backend, inclusion: { in: Storage::BACKENDS }
end
