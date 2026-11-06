# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.

ActiveRecord::Schema[8.0].define(version: 2026_11_04_000003) do
  create_table "api_tokens", force: :cascade do |t|
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
  end

  create_table "blob_contents", force: :cascade do |t|
    t.string "blob_id", limit: 1024, null: false
    t.binary "data", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_blob_contents_on_blob_id", unique: true
  end

  create_table "blobs", force: :cascade do |t|
    t.string "blob_id", limit: 1024, null: false
    t.bigint "size", null: false
    t.string "storage_backend", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_blobs_on_blob_id", unique: true
  end
end
