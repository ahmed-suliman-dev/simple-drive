# Content table used only by the "database" storage backend.
# Kept separate from the blobs metadata table, as the brief requires.
class CreateBlobContents < ActiveRecord::Migration[8.0]
  def change
    create_table :blob_contents do |t|
      t.string :blob_id, null: false, limit: 1024
      t.binary :data, null: false
      t.datetime :created_at, null: false
    end

    add_index :blob_contents, :blob_id, unique: true
  end
end
