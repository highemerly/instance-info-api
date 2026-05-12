# instance-info-api

Get fediverse server type by REST API.

- Return instance type (e.g. mastodon, misskey, friendica, pixelfed, ...)
- Return software version, total users, and status for fediverse instances
- Support some non-fediverse SNS (e.g. twitter, facebook, ...)
- Create cache

## Request to hosted services

```
GET https://anypost.dev/api/v1/instances/<instance-name>
```

Example of response:

- GET https://anypost.dev/api/v1/instances/mastodon.cloud

`{"name":"mastodon.cloud","type":"mastodon","version":"4.3.2","total_users":12345,"status":1,"source":"cache"}`

- GET https://anypost.dev/api/v1/instances/misskey.io

`{"name":"misskey.io","type":"misskey","version":"2025.3.1","total_users":98765,"status":1,"source":"fediverse.observer"}`

- GET https://anypost.dev/api/v1/instances/twitter.com

`{"name":"twitter.com","type":"twitter","source":"builtin"}`

`version`, `total_users`, and `status` come from fediverse.observer's GraphQL `node`
(`fullversion`, `total_users`, `status`). `status` is an integer (`1` = up). These
fields are omitted from the response when not available (e.g. non-fediverse cached
entries such as `twitter.com`).

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

### Prepare database

The cache database is a single SQLite file under `storage/`. Initialize it with:

```
$ RAILS_ENV=production bundle exec rails db:prepare
```

`db:prepare` is idempotent — it creates the database, loads the schema and seeds on the first run, and applies pending migrations on subsequent runs.

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
