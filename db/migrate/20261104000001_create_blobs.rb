# Metadata about every stored blob. The blob content itself never lives here;
# it lives in whichever storage backend was active when the blob was stored.
class CreateBlobs < ActiveRecord::Migration[8.0]
  def change
    create_table :blobs do |t|
      t.string :blob_id, null: false, limit: 1024
      t.bigint :size, null: false
      t.string :storage_backend, null: false
      t.timestamps
    end

    add_index :blobs, :blob_id, unique: true
  end
end
