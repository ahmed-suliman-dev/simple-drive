require "fileutils"
require "securerandom"

module Storage
  # Stores each blob as a file under a root directory.
  #
  # Layout: <root>/ab/cd/abcd...<64 hex chars>, from the SHA-256 of the id.
  # The two levels of sub-folders keep any one directory from growing huge.
  class LocalBackend < Base
    attr_reader :root

    def initialize(root:)
      super()
      @root = File.expand_path(root)
    end

    def store(blob_id, data)
      path = path_for(blob_id)
      FileUtils.mkdir_p(File.dirname(path))

      # Write to a temp file and rename it into place, so a crash mid-write
      # never leaves a half-written blob behind.
      tmp_path = "#{path}.#{SecureRandom.hex(6)}.tmp"
      File.binwrite(tmp_path, data)
      File.rename(tmp_path, path)
    rescue SystemCallError => e
      FileUtils.rm_f(tmp_path) if tmp_path
      raise Error, "local backend failed to store blob: #{e.message}"
    end

    def retrieve(blob_id)
      File.binread(path_for(blob_id))
    rescue Errno::ENOENT
      raise NotFound, "blob not found in local backend"
    rescue SystemCallError => e
      raise Error, "local backend failed to read blob: #{e.message}"
    end

    private

    def path_for(blob_id)
      name = object_name(blob_id)
      File.join(root, name[0, 2], name[2, 2], name)
    end
  end
end
