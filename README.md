# Simple Drive

A Ruby on Rails API for storing and retrieving blobs through one interface,
with four interchangeable storage backends:

| Backend    | Where the bytes go                                                  |
|------------|---------------------------------------------------------------------|
| `database` | The `blob_contents` table (separate from the metadata table)         |
| `local`    | Files under a configured directory                                  |
| `s3`       | Any S3-compatible service, via a **hand-written SigV4 HTTP client**  |
| `ftp`      | An FTP server (bonus)                                               |

All requests require a Bearer token.

## API

### Store a blob

```http
POST /v1/blobs
Authorization: Bearer <token>
Content-Type: application/json

{ "id": "any_valid_string_or_identifier", "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh" }
```

`201 Created`

```json
{ "id": "any_valid_string_or_identifier", "size": "27", "created_at": "2026-11-04T21:37:55Z" }
```

### Retrieve a blob

```http
GET /v1/blobs/any_valid_string_or_identifier
Authorization: Bearer <token>
```

`200 OK`

```json
{
  "id": "any_valid_string_or_identifier",
  "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh",
  "size": "27",
  "created_at": "2026-11-04T21:37:55Z"
}
```

`size` is in bytes and `created_at` is UTC (ISO 8601). `size` is returned as a
string to match the example in the brief. Ids may contain slashes and dots,
e.g. `GET /v1/blobs/photos/2024/cat.png`.

### Errors

Every error is JSON: `{ "error": "<code>", "message": "<human readable>" }`.

| Status | `error`                  | When                                             |
|--------|--------------------------|--------------------------------------------------|
| 400    | `invalid_json`           | The body is not valid JSON                       |
| 401    | `unauthorized`           | Missing or unknown Bearer token                  |
| 404    | `not_found`              | No blob with that id                             |
| 409    | `duplicate_id`           | A blob with that id already exists               |
| 422    | `invalid_id`             | `id` missing, not a string, or over 1024 chars   |
| 422    | `invalid_data`           | `data` missing or not valid Base64               |
| 500    | `storage_misconfigured`  | The backend's settings are missing or wrong      |
| 502    | `storage_error`          | The backend failed (S3/FTP down, disk error...)  |

## Running it

Requirements: Ruby 3.2+ (developed on 3.3). Docker is optional and only
needed to run MinIO and an FTP server locally.

### macOS / Linux

```bash
bundle install
cp .env.example .env          # choose STORAGE_BACKEND and its settings
bin/rails db:prepare
bin/rails "api_tokens:create[my-laptop]"   # prints a token once
bin/rails server              # http://localhost:3000
```

### Windows (PowerShell)

```powershell
bundle install
Copy-Item .env.example .env
ruby bin/rails db:prepare
ruby bin/rails "api_tokens:create[my-laptop]"
ruby bin/rails server
```

### Try it

```bash
TOKEN=<token from api_tokens:create>

curl -X POST http://localhost:3000/v1/blobs \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"id":"hello.txt","data":"SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh"}'

curl http://localhost:3000/v1/blobs/hello.txt -H "Authorization: Bearer $TOKEN"
```

### Demo console

With the server running, open <http://localhost:3000>. The page
(`public/index.html`, plain HTML and JavaScript) uses the same public API:
paste a token, store a file, retrieve it, and see which step of the request
path (token check, validation, metadata, storage) succeeded or failed, along
with the raw HTTP exchange. It is a convenience for trying the API; the API
itself does not depend on it.

### Using the S3 or FTP backend locally

```bash
docker compose up -d          # MinIO on :9000 (console :9001), FTP on :21
```

Then set `STORAGE_BACKEND=s3` (or `ftp`) in `.env` and restart the server.
The defaults in `.env.example` already match `docker-compose.yml`.

## Configuration

Everything is set through environment variables (or `.env`):

| Variable                | Used by | Default         |
|-------------------------|---------|-----------------|
| `STORAGE_BACKEND`       | all     | `database`      |
| `LOCAL_STORAGE_PATH`    | local   | required        |
| `S3_ENDPOINT`           | s3      | required, e.g. `https://s3.me-central-1.amazonaws.com` |
| `S3_BUCKET`             | s3      | required        |
| `S3_REGION`             | s3      | `us-east-1`     |
| `S3_ACCESS_KEY_ID`      | s3      | required        |
| `S3_SECRET_ACCESS_KEY`  | s3      | required        |
| `FTP_HOST`              | ftp     | required        |
| `FTP_PORT`              | ftp     | `21`            |
| `FTP_USERNAME`          | ftp     | required        |
| `FTP_PASSWORD`          | ftp     | required        |
| `FTP_DIRECTORY`         | ftp     | `simple-drive`  |
| `FTP_PASSIVE`           | ftp     | `true`          |

## Tests

```bash
bin/rails test        # Windows: ruby bin/rails test
```

The suite covers:

- **Integration** (`test/integration/blobs_api_test.rb`): authentication, the
  exact request/response formats from the brief, validation, duplicates,
  path-like ids, binary round-trips, and the database, local and S3 backends
  end to end through the API.
- **S3 signer**: checked against the worked examples in the
  [AWS SigV4 documentation](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html),
  so the signatures are verified against Amazon's own expected values.
- **Each backend**: S3 (HTTP stubbed with WebMock), FTP (fake client), local
  (temp directory), plus `BlobStore` transaction rollback and `ApiToken`.

## Design

```
BlobsController ──> BlobStore ──> Storage.for(name) ──> Storage::Base
   (HTTP, JSON,        (metadata +                         ├─ DatabaseBackend
    validation)         transaction)                       ├─ LocalBackend
                                                           ├─ S3Backend ── S3Signer
                                                           └─ FtpBackend
```

- **One interface.** Every backend subclasses `Storage::Base` and implements
  `store(blob_id, data)` and `retrieve(blob_id)`. The controller and
  `BlobStore` never know which backend is in use; adding a backend means adding
  one class and one line in `Storage.for`.
- **Metadata vs. content.** The `blobs` table holds only metadata (id, size,
  backend, timestamps). Content lives in the backend. The database backend uses
  its own `blob_contents` table.
- **Each blob remembers its backend.** `blobs.storage_backend` records where the
  bytes went, so changing `STORAGE_BACKEND` later does not break reads of older
  blobs.
- **No overwrites, no orphans.** `BlobStore#store` inserts the metadata row first
  inside a transaction (a unique index on `blob_id` rejects duplicates before
  any bytes are written), then writes to the backend. If the backend fails, the
  transaction rolls back.
- **Safe object names.** Ids are arbitrary text, so the file, S3 and FTP
  backends store each blob under the SHA-256 of its id. This rules out path
  traversal (`../../etc/passwd`) and every URL/filename encoding edge case.
  The original id stays in the metadata table.
- **Atomic local writes.** Files are written to a temp file and renamed into
  place, so a crash never leaves a half-written blob.

### S3 without an S3 library

`Storage::S3Signer` implements AWS Signature Version 4 with only `OpenSSL` and
`Digest`, and `Storage::S3Backend` sends plain `Net::HTTP` requests:

1. **Canonical request**: method, path, sorted query string, sorted lowercase
   headers, the list of signed headers, and the SHA-256 of the body.
2. **String to sign**: `AWS4-HMAC-SHA256`, the timestamp, the credential scope
   (`date/region/s3/aws4_request`), and the SHA-256 of the canonical request.
3. **Signing key**: `HMAC("AWS4" + secret, date)`, then chained through region,
   service, and `aws4_request`.
4. **Signature**: `HMAC(signing key, string to sign)` in hex, sent in the
   `Authorization` header with `x-amz-date` and `x-amz-content-sha256`.

Requests use path-style URLs (`<endpoint>/<bucket>/blobs/<sha256>`), which AWS
S3, MinIO, DigitalOcean Spaces and Linode all accept.

### Authentication

`bin/rails "api_tokens:create[name]"` generates a random 256-bit token and
prints it once. Only its SHA-256 digest is stored in `api_tokens`, so the
database never holds a usable token. Requests send
`Authorization: Bearer <token>`, and `last_used_at` records activity per token.

## Possible next steps

- Stream large blobs instead of holding them in memory (Base64 JSON bodies
  limit practical blob size anyway).
- `DELETE /v1/blobs/:id` and listing.
- Token revocation and expiry.
- Run the database backend on its own database connection (Rails multi-db).
