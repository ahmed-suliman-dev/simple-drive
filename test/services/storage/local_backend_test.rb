require "test_helper"

class Storage::LocalBackendTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir
    @backend = Storage::LocalBackend.new(root: @root)
  end

  teardown do
    FileUtils.remove_entry(@root)
  end

  test "stores and retrieves bytes" do
    data = (0..255).map(&:chr).join.b
    @backend.store("photos/cat.png", data)

    assert_equal data, @backend.retrieve("photos/cat.png")
  end

  test "keeps every file inside the root, even for path-like ids" do
    @backend.store("../../../etc/passwd", "safe")

    files = Dir.glob(File.join(@backend.root, "**", "*")).select { |path| File.file?(path) }
    assert_equal 1, files.size
    assert files.first.start_with?(@backend.root)
    assert_match(%r{/\h{2}/\h{2}/\h{64}\z}, files.first)
  end

  test "leaves no temp files behind" do
    @backend.store("a", "1")

    assert_empty Dir.glob(File.join(@root, "**", "*.tmp"))
  end

  test "raises NotFound for an unknown id" do
    assert_raises(Storage::NotFound) { @backend.retrieve("missing") }
  end
end
