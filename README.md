# instance-info-api

Get fediverse server type by REST API.

- Return instance type (e.g. mastodon, misskey, friendica, pixelfed, ...)
- Support some non-fediverse SNS (e.g. twitter, facebook, ...)
- Create cache

## Request to hosted services

```
GET https://anypost.dev/api/v1/instances/<instance-name>
```

Example of response:

- GET https://anypost.dev/api/v1/instances/mastodon.cloud

`{"name":"mastodon.cloud","type":"mastodon","source":"cache"}`

- GET https://anypost.dev/api/v1/instances/misskey.io

`{"name":"misskey.io","type":"misskey","source":"fediverse.observer"}`

- GET https://anypost.dev/api/v1/instances/twitter.com

`{"name":"twitter.com","type":"twitter","source":"cache"}`

## Run your own environments

### Pre-requirements

- Ruby 2.7
- Rails 7.0
- MySQL 8.0

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

If you use `instanceapi` database and `instanceapiuser` user in local databases,

```
$ mysql -u root
> CREATE DATABASE instanceapi;
> CREATE USER 'instanceapiuser'@'localhost' IDENTIFIED BY '*********';
> GRANT ALL ON instanceapi.* TO 'instanceapiuser'@'localhost';
```

In addition, create `.env` files for your environments.

```
$ vi .env.production

DB_HOST = 'localhost'
DB_NAME = 'instanceapi'
DB_USER = 'instanceapiuser'
DB_PASS = '*********'

$ RAILS_ENV=production bundle exec rails db:migrate
$ RAILS_ENV=production bundle exec rails db:seed
```

### Run

```
$ RAILS_ENV=production bundle exec rails server
```

Then, `curl http://localhost:3000/api/v1/instances/<instance-name>` may be respond desirable json.

## License

See `./LICENSE`
