# instance-info-api

Get fediverse server type by REST API.

- Return instance type (e.g. mastodon, misskey, friendica, pixelfed, ...)
- Return the specific software fork in a separate `software` field (e.g. `type=pleroma, software=akkoma`)
- Return software version, total users, and status for fediverse instances
- Support some non-fediverse SNS (e.g. twitter, facebook, ...)
- Create cache

## Request to hosted services

```
GET https://anypost.dev/api/v1/instances/<instance-name>
```

Example of response:

- GET https://anypost.dev/api/v1/instances/mastodon.cloud

`{"name":"mastodon.cloud","type":"mastodon","software":"mastodon","version":"4.3.2","total_users":12345,"status":1,"updated_at":"2026-05-13T03:21:00Z","source":"cache:fediverse.observer"}`

- GET https://anypost.dev/api/v1/instances/misskey.io

`{"name":"misskey.io","type":"misskey","software":"misskey","version":"2025.3.1","total_users":98765,"status":1,"updated_at":"2026-05-13T03:21:00Z","source":"fediverse.observer"}`

- GET https://anypost.dev/api/v1/instances/some-akkoma-instance.example

`{"name":"some-akkoma-instance.example","type":"pleroma","software":"akkoma","version":"3.x","total_users":42,"status":1,"updated_at":"2026-05-13T03:21:00Z","source":"fediverse.observer"}`

- GET https://anypost.dev/api/v1/instances/twitter.com

`{"name":"twitter.com","type":"twitter","updated_at":"2026-05-13T03:21:00Z","source":"builtin"}`

`type` is the canonical fediverse family (e.g. `mastodon`, `pleroma`, `misskey`,
`lemmy`). `software` is the specific implementation as reported by
fediverse.observer (e.g. `akkoma`, `firefish`, `sharkey`, `fedibird`). When a
fork is not yet mapped in `config/software_families.yml`, `type` falls back to
the raw softwarename so no information is lost.

`version`, `total_users`, and `status` come from fediverse.observer's GraphQL `node`
(`fullversion`, `total_users`, `status`). `status` is an integer (`1` = up). These
fields, along with `software`, are omitted from the response when not available
(e.g. non-fediverse cached entries such as `twitter.com`).

`updated_at` is the ISO 8601 timestamp of when this row was last written in our
cache database — i.e. when the data was last fetched from fediverse.observer
(or, for builtin entries, when seeds were loaded). It is omitted only when
there is no cache row (e.g. a DNS error path that never persists).

### `source` values and HTTP status codes

`source` describes where the response data came from. Cached responses prefix
the original source with `cache:` so clients can distinguish a fresh fetch
from a cached one.

| `source`                                      | HTTP status | Meaning                                                                  |
| --------------------------------------------- | ----------- | ------------------------------------------------------------------------ |
| `builtin`                                     | 200         | Hard-coded non-fediverse entry (e.g. twitter.com).                       |
| `fediverse.observer`                          | 200         | Fresh fetch from fediverse.observer.                                     |
| `fediverse.observer:cache-revalidated`        | 200         | Stale cache refreshed; software unchanged.                               |
| `fediverse.observer:cache-refleshed`          | 200         | Stale cache refreshed; software changed.                                 |
| `cache:fediverse.observer`                    | 200         | Cached fediverse.observer result, within TTL.                            |
| `cache:fediverse.observer:stale-fallback`     | 200         | Stale cache served because the refresh attempt could not reach observer. |
| `cache:cache-stale`                           | 200 / 404   | Stale cache kept after observer returned no data (404 when type=unknown).|
| `error:no-data`                               | 404         | Fresh fetch — observer has no record for this domain.                    |
| `cache:error:no-data`                         | 404         | Cached "no data" result, within TTL.                                     |
| `cache:error:no-data:stale-fallback`          | 404         | Cached "no data" served because observer could not be reached.           |
| `error:dns-error`                             | 400         | Domain failed DNS resolution. Not cached.                                |
| `error:observer-unavailable`                  | 503         | Could not reach fediverse.observer (timeout, network, malformed reply). Not cached. |

## Run your own environments

### Pre-requirements

- Ruby 3.3
- Rails 8.0
- SQLite 3 (used as a local cache store)

### Install

```
$ git clone https://github.com/highemerly/instance-info-api
$ cd instance-info-api
$ bundle install
```

### Create secret key SECRET_KEY_BASE

Create secret_key_base in your environments.

```
$ RAILS_ENV=production bundle exec rake secret
  <xxxxxxxxxxxxxxxx>   # <- remember it
$ cp .env.sample .env.production
$ vi .env.production

SECRET_KEY_BASE='<xxxxxxxxxxxxxxxx>'
```

### Obtain a fediverse.observer API key

Requests from datacenter IP ranges are blocked by Cloudflare with HTTP 403 unless they carry a valid API key. Generate one at <https://api.fediverse.observer/keygenerator.php> (keys are tied to an email, last about one year, and replace any previous key issued to the same email). Put it in `.env.production` (or your Kubernetes secret):

```
SWAPI_API_KEY='<the-key-you-received>'
```

Without this key the controller will still boot and serve cached responses, but live lookups against fediverse.observer return `503 error:observer-unavailable`.

### Prepare database

The cache database is a single SQLite file under `storage/`. Initialize it with:

```
$ RAILS_ENV=production bundle exec rails db:prepare
```

`db:prepare` is idempotent — it creates the database, loads the schema and seeds on the first run, and applies pending migrations on subsequent runs.

### Refresh the fediverse.observer GraphQL schema

The GraphQL client loads its schema from `db/swapi_schema.json` (checked into the repo) instead of running introspection against fediverse.observer at boot, so a flaky upstream response can no longer prevent Puma from starting. Refresh the file when the upstream schema changes:

```
$ bundle exec rake swapi:schema:dump
```

Commit the regenerated `db/swapi_schema.json` along with any client changes that depend on it.

### Run

```
$ RAILS_ENV=production bundle exec rails server
```

Then, `curl http://localhost:3000/api/v1/instances/<instance-name>` may be respond desirable json.

### Run with Docker

```
$ cp .env.sample .env.production   # set SECRET_KEY_BASE
$ docker compose up --build
```

The SQLite cache is persisted in the `sqlite_data` named volume.

## License

See `./LICENSE`
