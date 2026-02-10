# syntax=docker/dockerfile:1

# ============================================
# Stage 1: ビルド
# ============================================
FROM ruby:2.7.6-slim AS builder

WORKDIR /app

# ビルドに必要なパッケージをインストール
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    default-libmysqlclient-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Gemfile をコピーして依存関係をインストール
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# ============================================
# Stage 2: 本番実行環境
# ============================================
FROM ruby:2.7.6-slim AS runner

WORKDIR /app

# ランタイムに必要なパッケージをインストール
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    default-libmysqlclient-dev \
    && rm -rf /var/lib/apt/lists/*

# 非 root ユーザーを作成
RUN groupadd --system --gid 1001 rails && \
    useradd --system --uid 1001 --gid rails rails

# bundle をコピー
COPY --from=builder /app/vendor/bundle ./vendor/bundle
COPY --from=builder /usr/local/bundle/config /usr/local/bundle/config

# アプリケーションをコピー
COPY --chown=rails:rails . .

# bundler 設定
RUN bundle config set --local path 'vendor/bundle' && \
    bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test'

# 本番環境設定
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true

USER rails

EXPOSE 3000

# Puma で起動
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
