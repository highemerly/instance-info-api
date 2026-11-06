#!/usr/bin/env bash
# 本番のイメージを起動して、API が答えることを確かめる（smoke.yml から呼ぶ。手元でも同じ）。
# Puma が起動し、DB 準備（entrypoint の db:prepare + seed）が通ることと、最後に自前の Mastodon
# （handon.club）を実際に引き、本番と同じイメージ内の libcurl / DNS 経路で nodeinfo が取れることを見る。
#
# 使い方: .github/scripts/smoke.sh <イメージ>   例: docker build -t instance-info-api:smoke . && .github/scripts/smoke.sh instance-info-api:smoke
# 要るもの: docker・curl・jq・openssl。ポートは SMOKE_PORT（既定 3000）。
set -euo pipefail

image="${1:?image required}"
port="${SMOKE_PORT:-3000}"
name="instance-info-api-smoke"
base="http://127.0.0.1:${port}"

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" -p "${port}:3000" -e SECRET_KEY_BASE="$(openssl rand -hex 64)" "$image" >/dev/null
# 失敗したときに原因が分かるよう、終了時にコンテナのログを出してから消す
trap 'status=$?; if [ $status -ne 0 ]; then docker logs "$name" || true; fi; docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

for i in $(seq 1 30); do
  curl -sf "$base/api/v1/health/live" >/dev/null && break
  if [ "$i" = 30 ]; then
    echo "::error::the container did not start serving within 60s"
    exit 1
  fi
  sleep 2
done

expect_status() {
  local want="$1" path="$2" got
  # 接続できないときは curl が 000 を出して非 0 で終わる。set -e で黙って抜けずに、ステータスとして報告する
  got="$(curl -s -o /dev/null -w '%{http_code}' "$base$path" || true)"
  if [ "$got" != "$want" ]; then
    echo "::error::GET $path returned $got, want $want"
    return 1
  fi
  echo "GET $path -> $got"
}

expect_status 200 /api/v1/health/live
expect_status 200 /api/v1/health/ready
expect_status 200 /api/v1/instances/twitter.com
expect_status 400 '/api/v1/instances/twitter.com?source=fediverse.observer'
curl -sf "$base/api/v1/instances/handon.club" | tee /dev/stderr \
  | jq -e '.type == "mastodon" and .source == "nodeinfo" and (.total_users | type) == "number"' >/dev/null
echo
echo "smoke: OK"
