# instance-info-api

Tell what a fediverse server (or a well-known SNS) is, by REST API: its type
(mastodon, misskey, lemmy, ...), name, post length limit, thumbnail and icon,
registration status and activity. Results are cached.

## Request to hosted services

```
GET https://anypost.dev/api/v2/instances/<instance-name>
GET https://anypost.dev/api/v2/software
GET https://anypost.dev/api/v2/stats
```

`/api/v1/instances/<instance-name>` still works but is deprecated; see
[v1](#v1-deprecated) below.

### `GET /api/v2/instances/<instance-name>`

```json
{
  "domain": "misskey.io",
  "kind": "fediverse",
  "type": "misskey",
  "software": { "name": "misskey", "version": "2025.4.1-io.12b" },
  "node_name": "Misskey.io",
  "thumbnail_url": "https://media.misskeyusercontent.jp/misskey/65b25d3c-....jpg",
  "icon_url": "https://media.misskeyusercontent.jp/io/2f626cae-....png",
  "max_characters": { "halfwidth": 3000, "fullwidth": 3000 },
  "open_registrations": false,
  "usage": { "total_users": 744876, "active_month": null, "active_halfyear": null, "local_posts": 183922605 },
  "fetched_at": "2026-11-19T03:21:00Z",
  "cache": "hit"
}
```

```json
{
  "domain": "x.com",
  "kind": "service",
  "type": "twitter",
  "software": null,
  "node_name": "X",
  "thumbnail_url": null,
  "icon_url": null,
  "max_characters": { "halfwidth": 280, "fullwidth": 140 },
  "open_registrations": true,
  "usage": null,
  "fetched_at": null,
  "cache": "builtin"
}
```

Every key is always present; a value that isn't known is `null`.

| Key | Meaning |
| --- | --- |
| `domain` | The instance name after [normalization](#instance-name). |
| `kind` | `fediverse`, or `service` for a builtin non-fediverse SNS ([config/builtin_services.yml](config/builtin_services.yml)). |
| `type` | The fediverse family (`mastodon`, `pleroma`, `misskey`, `lemmy`, ...), or the service. Forks are folded into their family by [config/software_families.yml](config/software_families.yml); unmapped software keeps its own name. |
| `software` | `name` and `version` from nodeinfo's `software` (e.g. `akkoma` under `type` `pleroma`). |
| `node_name` | The server's display name. |
| `thumbnail_url` | A wide banner image (Mastodon's thumbnail, Misskey's banner, ...). |
| `icon_url` | A square icon; of several sizes, the smallest at least 192px wide. |
| `max_characters` | The longest post. `halfwidth` counts ASCII letters, `fullwidth` CJK characters; they differ only where a CJK character counts double (X, タイッツー). |
| `open_registrations` | Whether anyone can sign up. |
| `usage` | `total_users`, `active_month`, `active_halfyear`, `local_posts` from nodeinfo (Misskey and GoToSocial don't report active users). |
| `fetched_at` | When the data was fetched from the server. |
| `cache` | `hit` (from cache), `miss` (fetched now), `stale` (past its day; answered as is while it's refreshed in the background), `builtin`. |

Where the fields come from: nodeinfo for `software`, `open_registrations` and
`usage`; each software's instance API for `max_characters`, `thumbnail_url` and
`icon_url` (Mastodon-compatible `/api/v2/instance` and `/api/v1/instance`,
Misskey `/api/meta`, Lemmy `/api/v3/site`, PieFed `/api/alpha/site`, PeerTube
`/api/v1/config/about`). Software without such an API (Mbin, Hubzilla,
WriteFreely, ...) gets `null` there.

#### Caching

A fetch is cached for a day. After that, the next request gets the old data at
once (`cache: "stale"`) and a background job refreshes it
(stale-while-revalidate); only a server never seen before is fetched while the
request waits. A failed background refresh is retried after 10 minutes, and a
server whose nodeinfo is gone becomes `not_fediverse`.

Responses carry `Cache-Control` for browsers (`max-age`) and the CDN
(`s-maxage`). The CDN never keeps a row past the moment it goes stale here:

| Response | `Cache-Control` |
| --- | --- |
| `hit` / `miss` | `max-age=300, public, s-maxage=` time until stale, at most 6 hours |
| `stale` | `max-age=0, public, s-maxage=60` |
| `builtin`, `/software` | `max-age=3600, public, s-maxage=3600` |
| `not_fediverse` | `max-age=300, public, s-maxage=` time until stale, at most 1 hour |
| `invalid_name`, `unresolvable` | `max-age=60, public, s-maxage=300` |
| `upstream_unavailable` | `no-store` |
| `/stats` | `max-age=60, public, s-maxage=300` |

Errors:

```json
{ "domain": "example.com", "error": { "code": "not_fediverse", "message": "no nodeinfo; not a fediverse server" } }
```

| `error.code` | HTTP | Meaning |
| --- | --- | --- |
| `invalid_name` | 400 | Not a hostname, even after normalization. |
| `unresolvable` | 404 | The domain doesn't resolve. Not cached. |
| `not_fediverse` | 404 | No nodeinfo at the domain. Cached for a day. |
| `upstream_unavailable` | 503 | The server couldn't be reached. Not cached. |

### Instance name

`<instance-name>` is normalized before lookup (in v1 too):

| Input                                         | Looked up as         |
| --------------------------------------------- | -------------------- |
| `Mastodon.Social`, `mastodon.social.`, `mastodon.social:443` | `mastodon.social` |
| `@alice@mastodon.social`, `alice@mastodon.social` | `mastodon.social` (the handle's domain; WebFinger is not consulted) |
| `ｍａｓｔｏｄｏｎ．ｓｏｃｉａｌ` (fullwidth)        | `mastodon.social`    |
| `例え.jp` (IDN)                                | `xn--r8jz45g.jp`     |

A port other than 443, or anything that isn't a hostname after this, is
`invalid_name`. URLs aren't accepted (the path can't carry `/`); pass the host.
A leading `www.` is kept as is.

### `GET /api/v2/software`

The fediverse families and the software names folded into each, and the builtin
services with their domains and limits:

```json
{
  "fediverse": [{ "type": "mastodon", "software": ["mastodon", "hometown", "glitch-soc", "fedibird"] }, ...],
  "services": [{ "type": "twitter", "node_name": "X", "domains": ["twitter.com", "x.com"],
                 "max_characters": { "halfwidth": 280, "fullwidth": 140 }, "open_registrations": true }, ...]
}
```

### `GET /api/v2/stats`

Counts of what the cache holds — the servers looked up through this API, not
the whole fediverse. The cache belongs to the Pod and starts over when the Pod
is replaced; `since` is its oldest entry.

```json
{
  "pod": "instance-info-api-5d9c...",
  "generated_at": "2026-11-19T03:21:00Z",
  "since": "2026-11-12T10:00:00Z",
  "instances": { "fediverse": 1234, "not_fediverse": 56 },
  "types": { "mastodon": 800, "misskey": 300, ... },
  "software": { "mastodon": 700, "misskey": 200, "sharkey": 60, ... }
}
```

### v1 (deprecated)

```
GET https://anypost.dev/api/v1/instances/<instance-name>
```

`{"name":"misskey.io","type":"misskey","software":"misskey","version":"2025.3.1","total_users":98765,"status":null,"updated_at":"2026-05-13T03:21:00Z","source":"nodeinfo"}`

`{"name":"twitter.com","type":"twitter","source":"builtin"}`

v1 returns `name`, `type`, `software`, `version`, `total_users`, `status`,
`updated_at` and `source`, omitting the ones that aren't available (builtin
services have only `name`, `type` and `source`). For an unknown server
`software` and `version` are `"unknown"`. `status` is always `null` for
nodeinfo data; rows cached from fediverse.observer carried its integer status.

`?source=nodeinfo` is accepted and changes nothing. fediverse.observer shut
down in October 2026; `?source=fediverse.observer` and any other value return
HTTP 400 with a JSON body listing the valid options. The observer client is
kept in the codebase in case the service returns.

v1 refreshes a stale row while the request waits (no background refresh).
`source` says where the data came from; cached responses prefix the original
source with `cache:`.

| `source`                                      | HTTP status | Meaning                                                                  |
| --------------------------------------------- | ----------- | ------------------------------------------------------------------------ |
| `builtin`                                     | 200         | Builtin non-fediverse service (e.g. twitter.com).                        |
| `nodeinfo`                                    | 200         | Fresh fetch via direct nodeinfo.                                         |
| `nodeinfo:cache-revalidated`                  | 200         | Stale cache refreshed via nodeinfo; software unchanged.                  |
| `nodeinfo:cache-refleshed`                    | 200         | Stale cache refreshed via nodeinfo; software changed.                    |
| `cache:nodeinfo`                              | 200         | Cached nodeinfo result, within TTL.                                      |
| `cache:nodeinfo:stale-fallback`               | 200         | Stale cache served because every refresh attempt was unavailable.        |
| `error:no-data`                               | 404         | Fetched now (fresh or refreshing a stale row) — no nodeinfo at this domain. |
| `cache:error:no-data`                         | 404         | Cached "no data" result, within TTL.                                     |
| `cache:error:no-data:stale-fallback`          | 404         | Cached "no data" served because every upstream was unavailable.          |
| `error:invalid-name`                          | 400         | The name isn't a hostname, even after normalization. Not cached.         |
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

Changes go through pull requests; direct pushes to `main` are rejected. See [docs/development.md](docs/development.md) for the setup, the CI, the release steps and the reasons behind them.

CI sets `LIVE_NODEINFO_HOST=handon.club`, so `test/integration/live_nodeinfo_test.rb` also does a real nodeinfo lookup against that Mastodon server. Locally the test is skipped unless you set the variable:

```
$ LIVE_NODEINFO_HOST=handon.club bin/rails test
```

Releases are tagged `vX.Y.Z` (from the **Tag a release** workflow in the Actions tab, or by pushing a tag). Each release runs every check, publishes `ghcr.io/highemerly/instance-info-api` as `X.Y.Z`, `X.Y` and `latest`, smoke-tests that image, and creates a GitHub Release once everything passes. Images were published as `ghcr.io/highemerly/anypost-api` until 1.0.0.

## License

See `./LICENSE`
