# syntax=docker/dockerfile:1

FROM ruby:3.3.6-slim

WORKDIR /app

# 必要なパッケージをインストール
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libsqlite3-dev \
    libyaml-dev \
    libcurl4 \
    git \
    && rm -rf /var/lib/apt/lists/*

# 非 root ユーザーを作成
RUN groupadd --system --gid 1001 rails && \
    useradd --system --uid 1001 --gid rails rails

# Gemfile をコピーして依存関係をインストール
COPY Gemfile Gemfile.lock ./

# bundler をインストール (Ruby 3.3 同梱のものを利用)
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# アプリケーションをコピー
COPY --chown=rails:rails . .

# 本番環境設定
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true

# tmp ディレクトリの権限設定
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log && \
    chown -R rails:rails tmp log

USER rails

# storage ディレクトリの存在を保証 (volume マウント前のフォールバック)
RUN mkdir -p storage

EXPOSE 3000

# 起動時に db:prepare を実行してから Puma を起動
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
