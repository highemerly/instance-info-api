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

`{"name":"mastodon.cloud","type":"mastodon","software":"mastodon","version":"4.3.2","total_users":12345,"status":null,"updated_at":"2026-05-13T03:21:00Z","source":"cache:nodeinfo"}`

- GET https://anypost.dev/api/v1/instances/misskey.io

`{"name":"misskey.io","type":"misskey","software":"misskey","version":"2025.3.1","total_users":98765,"status":null,"updated_at":"2026-05-13T03:21:00Z","source":"nodeinfo"}`

- GET https://anypost.dev/api/v1/instances/some-akkoma-instance.example

`{"name":"some-akkoma-instance.example","type":"pleroma","software":"akkoma","version":"3.x","total_users":42,"status":null,"updated_at":"2026-05-13T03:21:00Z","source":"nodeinfo"}`

- GET https://anypost.dev/api/v1/instances/twitter.com

`{"name":"twitter.com","type":"twitter","updated_at":"2026-05-13T03:21:00Z","source":"builtin"}`

`type` is the canonical fediverse family (e.g. `mastodon`, `pleroma`, `misskey`,
`lemmy`). `software` is the specific implementation as reported by the
instance's nodeinfo `software.name` (e.g. `akkoma`, `firefish`, `sharkey`,
`fedibird`). When a fork is not yet mapped in `config/software_families.yml`,
`type` falls back to the raw software name so no information is lost.

`version` and `total_users` come from nodeinfo's `software.version` and
`usage.users.total`. These fields, along with `software`, are omitted from the
response when not available (e.g. non-fediverse cached entries such as
`twitter.com`).

`status` is always `null` for nodeinfo-sourced data — nodeinfo doesn't expose
a monitoring history, so the field is emitted as `null` instead of being
omitted, to make the gap explicit. Rows cached from fediverse.observer (see
below) still carry its integer status (`1` = up) until they are refreshed.

`updated_at` is the ISO 8601 timestamp of when this row was last written in our
cache database — i.e. when the data was last fetched upstream (or, for builtin
entries, when seeds were loaded). It is omitted only when there is no cache row
(e.g. a DNS error path that never persists).

### Data source

Live lookups fetch the instance's nodeinfo directly
(`/.well-known/nodeinfo`, then the highest-version schema document it links).
`?source=nodeinfo` is accepted for compatibility and behaves the same as the
default.

```
GET /api/v1/instances/<name>?source=nodeinfo
```

fediverse.observer shut down in October 2026 and is no longer queried.
`?source=fediverse.observer` and any other value return HTTP 400 with a JSON
body listing the valid options. The observer client is kept in the codebase in
case the service returns.

### `source` values and HTTP status codes

`source` describes where the response data came from. Cached responses prefix
the original source with `cache:` so clients can distinguish a fresh fetch
from a cached one.

| `source`                                      | HTTP status | Meaning                                                                  |
| --------------------------------------------- | ----------- | ------------------------------------------------------------------------ |
| `builtin`                                     | 200         | Hard-coded non-fediverse entry (e.g. twitter.com).                       |
| `nodeinfo`                                    | 200         | Fresh fetch via direct nodeinfo.                                         |
| `nodeinfo:cache-revalidated`                  | 200         | Stale cache refreshed via nodeinfo; software unchanged.                  |
| `nodeinfo:cache-refleshed`                    | 200         | Stale cache refreshed via nodeinfo; software changed.                    |
| `cache:nodeinfo`                              | 200         | Cached nodeinfo result, within TTL.                                      |
| `cache:nodeinfo:stale-fallback`               | 200         | Stale cache served because every refresh attempt was unavailable.        |
| `cache:cache-stale`                           | 200 / 404   | Stale cache kept after the upstream returned no data (404 when type=unknown). |
| `error:no-data`                               | 404         | Fresh fetch — no upstream had a record for this domain.                  |
| `cache:error:no-data`                         | 404         | Cached "no data" result, within TTL.                                     |
| `cache:error:no-data:stale-fallback`          | 404         | Cached "no data" served because every upstream was unavailable.          |
| `error:dns-error`                             | 400         | Domain failed DNS resolution. Not cached.                                |
| `error:nodeinfo-unavailable`                  | 503         | The nodeinfo fetch was unavailable (network error, 50x, ...). Not cached. |
| `cache:fediverse.observer`                    | 200         | Legacy: row cached from fediverse.observer before it shut down, within TTL. |
| `cache:fediverse.observer:stale-fallback`     | 200         | Legacy observer row served because the nodeinfo refresh was unavailable. |

### Health endpoints

| Endpoint                  | Use it for                  | Behaviour                                                                                                         |
| ------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `GET /api/v1/health/live` | k8s **liveness** probe      | Returns 200 as long as Puma serves requests. Doesn't touch the DB or upstreams, so external outages can't restart the Pod. |
| `GET /api/v1/health/ready`| k8s **readiness** probe     | Returns 200 when the cache DB is reachable, 503 otherwise. Excludes upstream health on purpose — nodeinfo failures are surfaced per request, not by removing the Pod from the Service. |
| `GET /api/v1/health/sources` | observability dashboards | Returns this Pod's in-memory tally of per-source success/failure events. Always 200 even when every upstream is down — not suitable as a probe. |

`/health/sources` records each failure to the Rails log as a structured
`source_failure name=... status=... domain=... message=...` line for log
aggregators. State is per-Pod and resets on restart; aggregate across replicas
externally.

Example Deployment probe configuration:

```yaml
livenessProbe:
  httpGet: { path: /api/v1/health/live, port: 3000 }
  initialDelaySeconds: 10
  periodSeconds: 10
readinessProbe:
  httpGet: { path: /api/v1/health/ready, port: 3000 }
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Run your own environments

### Pre-requirements

- Ruby 4.0
- Rails 8.1
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

### Obtain a fediverse.observer API key (currently unused)

fediverse.observer shut down in October 2026, so this key is not needed for now. The notes below are kept for if the service comes back and is re-enabled.

Requests from datacenter IP ranges are blocked by Cloudflare with HTTP 403 unless they carry a valid API key. Generate one at <https://api.fediverse.observer/keygenerator.php> (keys are tied to an email, last about one year, and replace any previous key issued to the same email). Put it in `.env.production` (or your Kubernetes secret):

```
SWAPI_API_KEY='<the-key-you-received>'
```

Without this key, observer lookups fail with Cloudflare 403.

### Prepare database

The cache database is a single SQLite file under `storage/`. Initialize it with:

```
$ RAILS_ENV=production bundle exec rails db:prepare
```

`db:prepare` is idempotent — it creates the database, loads the schema and seeds on the first run, and applies pending migrations on subsequent runs.

### Refresh the fediverse.observer GraphQL schema (currently unused)

Only relevant if fediverse.observer is re-enabled. The GraphQL client loads its schema from `db/swapi_schema.json` (checked into the repo) instead of running introspection against fediverse.observer at boot, so a flaky upstream response can no longer prevent Puma from starting. Refresh the file when the upstream schema changes:

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

## CI / Release

Every push to any branch runs the test suite and `bundle-audit` (`.github/workflows/ci.yml`).
CI sets `LIVE_NODEINFO_HOST=handon.club`, so `test/integration/live_nodeinfo_test.rb` also does a real nodeinfo lookup against that Mastodon server. Locally the test is skipped unless you set the variable:

```
$ LIVE_NODEINFO_HOST=handon.club bin/rails test
```

To release, push a `v*` tag:

```
$ git tag v1.0.0
$ git push origin v1.0.0
```

`.github/workflows/docker-build.yml` then:

1. Runs the same checks in parallel with the image build.
2. Builds `ghcr.io/highemerly/anypost-api` for `linux/amd64` with `--pull --no-cache`, so OS security updates are always picked up, and smoke-tests the image.
3. Pushes it as `1.0.0`, `1.0` and `latest`.
4. Opens a PR against `highemerly/k8sg1-repo` that bumps `manifests/anypost/prd/api.yaml`. Flux deploys it once the PR is merged.

To rebuild without a new tag (e.g. to pick up base image security fixes), run the workflow manually from the Actions tab with a tag name such as `v1.0.1`. Opening the k8sg1-repo PR needs the `K8SG1_PAT` repository secret.

## License

See `./LICENSE`
