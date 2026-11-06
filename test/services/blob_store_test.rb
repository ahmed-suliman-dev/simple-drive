require "test_helper"

class BlobStoreTest < ActiveSupport::TestCase
  test "stores data and metadata together" do
    blob = BlobStore.new(backend_name: "database").store("id-1", "hello")

    assert_equal 5, blob.size
    assert_equal "database", blob.storage_backend
    assert_equal "hello", BlobContent.find_by!(blob_id: "id-1").data
  end

  test "raises DuplicateBlob for an existing id" do
    store = BlobStore.new(backend_name: "database")
    store.store("id-1", "first")

    assert_raises(BlobStore::DuplicateBlob) { store.store("id-1", "second") }
    assert_equal "first", BlobContent.find_by!(blob_id: "id-1").data
  end

  test "rolls back the metadata when the backend fails" do
    failing = Storage::Base.new
    def failing.store(*) = raise(Storage::Error, "disk full")

    assert_raises(Storage::Error) { BlobStore.new(backend_name: "local", backend: failing).store("id-1", "x") }
    assert_equal 0, Blob.count
  end

  test "raises BlobNotFound for an unknown id" do
    assert_raises(BlobStore::BlobNotFound) { BlobStore.new.retrieve("nope") }
  end

  test "rejects an unknown backend name" do
    assert_raises(Storage::ConfigurationError) { BlobStore.new(backend_name: "tape").store("a", "b") }
  end
end
