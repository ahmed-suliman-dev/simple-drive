require "test_helper"

class Storage::FtpBackendTest < ActiveSupport::TestCase
  # In-memory stand-in for Net::FTP with the methods the backend uses.
  class FakeFtp
    attr_reader :files, :directories, :closed

    def initialize(files)
      @files = files
      @directories = []
      @closed = false
    end

    def mkdir(dir)
      raise Net::FTPPermError, "550 Directory exists" if @directories.include?(dir)

      @directories << dir
    end

    def storbinary(command, io, _block_size)
      @files[command.delete_prefix("STOR ")] = io.read
    end

    def retrbinary(command, _block_size)
      path = command.delete_prefix("RETR ")
      raise Net::FTPPermError, "550 No such file" unless @files.key?(path)

      yield @files[path]
    end

    def close
      @closed = true
    end
  end

  setup do
    @files = {}
    @connections = []
    @backend = Storage::FtpBackend.new(
      host: "ftp.test", username: "u", password: "p", directory: "simple-drive",
      connection_factory: -> { FakeFtp.new(@files).tap { |ftp| @connections << ftp } }
    )
  end

  test "stores and retrieves bytes" do
    data = "\x00\x01binary".b
    @backend.store("report.pdf", data)

    assert_equal data, @backend.retrieve("report.pdf")
    assert_equal ["simple-drive/#{Digest::SHA256.hexdigest('report.pdf')}"], @files.keys
  end

  test "closes every connection" do
    @backend.store("a", "1")
    @backend.retrieve("a")

    assert @connections.all?(&:closed)
  end

  test "raises NotFound when the server answers 550" do
    assert_raises(Storage::NotFound) { @backend.retrieve("missing") }
  end

  test "wraps connection failures in Storage::Error" do
    backend = Storage::FtpBackend.new(
      host: "ftp.test", username: "u", password: "p",
      connection_factory: -> { raise Errno::ECONNREFUSED }
    )

    assert_raises(Storage::Error) { backend.store("a", "1") }
  end
end
