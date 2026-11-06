require "net/ftp"
require "stringio"

module Storage
  # Stores each blob as a file in one directory on an FTP server.
  class FtpBackend < Base
    BLOCK_SIZE = 64 * 1024

    # connection_factory lets tests swap in a fake FTP client.
    def initialize(host:, username:, password:, port: 21, directory: "simple-drive", passive: true, connection_factory: nil)
      super()
      @directory = directory.to_s.delete_suffix("/")
      @connection_factory = connection_factory || lambda {
        Net::FTP.new(host, port: port, username: username, password: password, passive: passive)
      }
    end

    def store(blob_id, data)
      with_connection do |ftp|
        ensure_directory(ftp)
        ftp.storbinary("STOR #{remote_path(blob_id)}", StringIO.new(data), BLOCK_SIZE)
      end
    rescue Net::FTPPermError => e
      raise Error, "FTP STOR failed: #{e.message.strip}"
    end

    def retrieve(blob_id)
      with_connection do |ftp|
        buffer = String.new(encoding: Encoding::BINARY)
        ftp.retrbinary("RETR #{remote_path(blob_id)}", BLOCK_SIZE) { |chunk| buffer << chunk }
        buffer
      end
    rescue Net::FTPPermError => e
      # 550 = file unavailable (not found / no access).
      raise NotFound, "blob not found in FTP backend" if e.message.start_with?("550")

      raise Error, "FTP RETR failed: #{e.message.strip}"
    end

    private

    def with_connection
      ftp = @connection_factory.call
      yield ftp
    rescue Net::FTPPermError
      raise
    rescue Net::FTPError, SocketError, SystemCallError, Timeout::Error, IOError => e
      raise Error, "FTP error: #{e.class}: #{e.message.to_s.strip}"
    ensure
      ftp&.close
    end

    def ensure_directory(ftp)
      return if @directory.empty?

      ftp.mkdir(@directory)
    rescue Net::FTPPermError
      # 550 here means it already exists, which is what we want.
    end

    def remote_path(blob_id)
      @directory.empty? ? object_name(blob_id) : "#{@directory}/#{object_name(blob_id)}"
    end
  end
end
