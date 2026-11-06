#!/usr/bin/env bash
# ブランチ push の CI（ci.yml）で、どのジョブ（checks / smoke）を回すかを決める。
# main との差分ファイルを見て、変更が影響しうるジョブだけ true にする。
#
# 方針（docs/development.md「CI」）:
# - アプリ・依存に触れたら両方回す
# - 下の一覧にないファイルは両方回す（知らない種類の変更を素通しさせない）
# - release/*（リリースの準備だけ）は何も回さない。リリース時に全部回す
#
# 使い方: ci-targets.sh <ブランチ名>。GITHUB_OUTPUT があればそこへ、無ければ標準出力へ書く（手元で試せる）。
set -euo pipefail

branch="${1:?branch name required}"
checks=false
smoke=false

if [[ "$branch" != release/* ]]; then
  base="$(git merge-base origin/main HEAD)"
  while IFS= read -r file; do
    case "$file" in
      # 動作に影響しないもの（ドキュメント・Claude Code の設定・ローカル hook・GitHub の設定・手元用のファイル）
      *.md | docs/* | .claude/* | .githooks/* | .github/rulesets/* | .github/renovate.json5 | .github/release.yml | LICENSE | .gitignore | .gitattributes | .env.sample) ;;
      # 手元で動かすためだけ（CI では使わない）
      docker-compose.yml) ;;
      # タグ push でしか動かない（ブランチでは確かめようがない）
      .github/workflows/docker-build.yml | .github/workflows/tag-release.yml) ;;
      # ワークフロー単体の変更（Actions の更新など）は、それを使うジョブだけ
      .github/workflows/checks.yml) checks=true ;;
      .github/workflows/smoke.yml | .github/scripts/smoke.sh) smoke=true ;;
      # テストはイメージの動作に関係しない
      test/*) checks=true ;;
      # イメージの組み立てと起動は minitest に関係しない
      Dockerfile | .dockerignore | bin/docker-entrypoint) smoke=true ;;
      *) checks=true; smoke=true ;;
    esac
  done < <(git diff --name-only "$base" HEAD)
fi

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "checks=$checks"
  echo "smoke=$smoke"
} >> "$out"
