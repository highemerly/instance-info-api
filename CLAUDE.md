# CLAUDE.md

## 概要

AnyPost（https://anypost.dev）の API。`/api/v1/instances/{name}` で、Fediverse のサーバーの種類（mastodon・misskey など）を
nodeinfo から引いて返す Rails 8.1（API モード）のアプリ。キャッシュは SQLite。本番は Docker のイメージで k8s に載る。

## ブランチ（必ず守ること）

- **main へ直接コミットしない。** 作業を始めるときにブランチを切り、PR で取り込む（手順と理由は `docs/development.md`）

## 公開リポジトリ

- インフラの非公開の情報（マニフェストのリポジトリ名・パス、クラスタの内部の名前や IP）をコード・docs・コミットメッセージ・PR に書かない。
  ワークフローで要るものはシークレットに置く（Actions のログも公開される）
- コミットの作者のメールは GitHub の noreply（`3039555+highemerly@users.noreply.github.com`）にする（セットアップは `docs/development.md`）

## コマンド

- `bin/rails test` - テスト（CI と同じ。`LIVE_NODEINFO_HOST=handon.club` を付けると本物のサーバーへの取得も回す）
- `docker compose up --build` - 本番と同じイメージで起動（`.env.production` が要る。README 参照）
