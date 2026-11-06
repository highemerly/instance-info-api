# 開発

## セットアップ

Ruby は [.ruby-version](../.ruby-version) に従う（CI も同じファイルを読む。Gemfile と Dockerfile のベースイメージの版も揃える）。

```bash
bundle install
bin/rails db:prepare
bin/rails test
```

clone ごとに1回:

```bash
git config core.hooksPath .githooks                                    # main 上のコミットを拒否する（下の「ブランチと PR」）
git config user.email 3039555+highemerly@users.noreply.github.com      # 公開リポジトリなので、コミットの作者に個人のメールを出さない
```

## ブランチと PR

- **main へは直接コミット・push しない。** 変更は必ずブランチを切り、PR → CI 緑 → squash マージで取り込む
- 手元: [.githooks/pre-commit](../.githooks/pre-commit) が main 上のコミットを拒否する（有効化は上のセットアップ）
- サーバー側: GitHub の ruleset（定義は [.github/rulesets/main.json](../.github/rulesets/main.json)）が
  main への push を拒否する。タグは ruleset の対象外（リリースのタグは main に直接打つ）

### ruleset の中身と理由

| ルール | 設定 | 理由 |
|---|---|---|
| PR 必須 | 承認数 0 | 一人運用で、自分の PR は自分で承認できないため |
| マージ方式 | squash のみ＋linear history | 「1変更＝1コミット」の履歴を保つ |
| 必須チェック | `ci-result`（checks / smoke のうち走ったものの結果をまとめたもの） | ブランチへの push で [ci.yml](../.github/workflows/ci.yml) が付ける。ジョブは差分で間引く（下の「CI」）ので、個別に必須にするとスキップされたジョブに結果が付かずマージできなくなる。必須でないチェックは赤でもマージできるので、マージ前に見たい検査は全部 `ci-result` に入れる |
| 最新化の強制 | しない（strict=false） | 依存更新の PR が並んだとき、1件マージするたびに全件を rebase・再 CI させないため |
| force push・削除 | 禁止 | |
| バイパス | なし（管理者も対象） | |
| 作者の紐づかないコミットの追加承認 | 求めない | 省略すると true が入り、アカウントに紐づかない作者のコミットがあると自分で承認できずマージできなくなる |

ruleset を変えたら JSON を直して反映する（作成時は POST、以降は `gh api repos/highemerly/instance-info-api/rulesets` で id を引いて PUT）:

```bash
gh api -X POST repos/highemerly/instance-info-api/rulesets --input .github/rulesets/main.json
gh api -X PUT repos/highemerly/instance-info-api/rulesets/<id> --input .github/rulesets/main.json
```

### リポジトリの設定

| 設定 | 値 | 理由 |
|---|---|---|
| マージ方式 | squash だけ許可 | ruleset と同じ。画面で別の方式を選べないようにする |
| squash のコミットメッセージ | PR タイトルだけ（本文は空） | ブランチ上の途中のコミットの一覧を main の履歴に持ち込まない |
| マージ後のブランチ | 自動で削除 | |
| auto-merge | 有効 | CI が緑になったらマージ、を予約できるようにする |

## CI

[ci.yml](../.github/workflows/ci.yml) が main 以外のブランチへの push で、**差分が影響しうるジョブだけ**を回す。
判定は [ci-targets.sh](../.github/scripts/ci-targets.sh)（main との merge-base からの差分ファイルで決める。
`.github/scripts/ci-targets.sh <ブランチ名>` で手元でも試せる。見るのはコミット済みの差分だけ）。

| 変更 | checks（minitest・bundler-audit） | smoke（本番イメージのビルドと起動してのスモーク） |
|---|---|---|
| `app/**`・`config/**`・`db/**`・依存（Gemfile・Gemfile.lock・`.ruby-version`）など、下に無いもの全部 | ✓ | ✓ |
| `test/**` | ✓ | – |
| `Dockerfile`・`.dockerignore`・`bin/docker-entrypoint` | – | ✓ |
| ワークフロー（checks.yml / smoke.yml・smoke.sh） | そのワークフローのジョブだけ | 同左 |
| ドキュメント（`*.md`・`docs/**`）・`.claude/**`・`.githooks/**`・ruleset・Renovate 設定・`.github/release.yml`・LICENSE・`.env.sample`・`docker-compose.yml`（手元用）・docker-build.yml・tag-release.yml | – | – |
| `release/*` ブランチ（リリースの準備だけ） | – | – |

- 結果は `ci-result` に集まる（main の必須チェックはこれだけにする）。成功とスキップは通し、失敗とキャンセルは落とす
- **main への push では回さない。** マージ前に同じ中身をブランチで通しているため
- **タグ push（リリース）では全部回す。** [docker-build.yml](../.github/workflows/docker-build.yml) が
  checks をビルドと並べて回し、スモークは push したイメージそのもので回す。全部が緑のときだけ Release とデプロイの PR を作る。
  ブランチで省いた検査で壊れていた場合は、ここで止まる
- ブランチのスモークのイメージのビルドは、タグのビルドがレジストリに積む `buildcache` を読む（イメージは公開なのでログインは要らない）
- bundler-audit は advisory DB を毎回最新にするので、コードを変えていなくても、新しく公開された脆弱性で落ちることがある。
  そのときは該当の gem を `bundle update --patch --conservative <gem>` で上げる PR を先に出す

### スモーク

[smoke.sh](../.github/scripts/smoke.sh) が本番のイメージを起動し、API を curl で呼んで確かめる（画面が無いので Playwright は使わない）。
ヘルスチェック・組み込みの行（twitter.com）・廃止したソースの 400 に加えて、自前の Mastodon（handon.club）を実際に引き、
**イメージの中の libcurl・Typhoeus で nodeinfo が取れること**を見る。手元でも同じ:

```bash
docker build -t instance-info-api:smoke . && .github/scripts/smoke.sh instance-info-api:smoke
```

## リリース

本番は、Flux で同期している k8s のマニフェストのリポジトリ（非公開）が指すイメージ。版は `vX.Y.Z` のタグで決める。

マニフェストのリポジトリの名前とパスはこのリポジトリに書かない（Actions のログも公開されるため）。
ワークフローはシークレットから読む:

| シークレット | 中身 |
|---|---|
| `K8SG1_REPO` | マニフェストのリポジトリ（`owner/name`） |
| `K8SG1_MANIFEST_PATHS` | 書き換える prd のマニフェストのパス（スペース区切り） |
| `K8SG1_PAT` | そのリポジトリへ PR を出すトークン（Contents と Pull requests の Read and write） |

**版はタグだけに持つ**（版を上げる PR は要らない）。

1. Actions の画面の **Tag a release**（[tag-release.yml](../.github/workflows/tag-release.yml)）を main で実行し、
   上げ方を選ぶ。main の先頭に次の版のタグを打ち、そのまま docker-build.yml を呼ぶ。手元からは:
   ```bash
   gh workflow run tag-release.yml --ref main -f bump=patch
   ```
   | 上げ方 | いつ |
   |---|---|
   | patch | 修正と依存の更新だけ（ベースイメージの OS のセキュリティ修正を取り込むための作り直しも） |
   | minor | 新しい機能（利用者・運用者から見てできることが増えた） |
   | major | 互換性を崩す |

   手元でタグを打って push しても同じことが起きる（飛び番の版を出すとき）:
   `git switch main && git pull && git tag vX.Y.Z && git push origin vX.Y.Z`
2. [docker-build.yml](../.github/workflows/docker-build.yml) が動く:
   1. **検査を全部回す**（ブランチで差分により省いたものも）。checks はビルドと並走し、
      スモークは **push したイメージそのもの**で回す（作り直したイメージで通っても、デプロイするものの確認にならない）
   2. イメージはベースイメージを pull し、**キャッシュを読まずに**組み直す（apt のレイヤがキャッシュされると
      OS のセキュリティ修正が入らないため）。`X.Y.Z`・`X.Y`・`latest` で GHCR（公開）へ push する。
      **イメージは検査の結果を待たずに push され、`latest` も動く。本番は版を固定していて、`latest` はデプロイに使わない**
   3. 全部が緑のときだけ **GitHub Release** を作る（タグごと・パッチも含む）。Release がある版＝デプロイしてよい版
   4. 同じ条件で、マニフェストのリポジトリへ「Update instance-info-api to X.Y.Z」の PR を出す（ラベル `app-update`）
3. **その PR のマージがそのまま本番へのデプロイになる**（Flux が約1分で反映）。マニフェストのリポジトリには
   必須チェックが無いので、そちらの CI が緑かを目で見てからマージする

DB（SQLite）はキャッシュで、起動時の `db:prepare` がマイグレーションを当てる。手で当てるマイグレーションは無い。

### GitHub Release のノート

GitHub の自動生成（前回のタグからマージされた PR の一覧と Full Changelog・英語）。分類は
[.github/release.yml](../.github/release.yml) で、Renovate の PR（`dependencies` ラベル）を
`Dependencies` に、それ以外を `Changes` に分ける。同じノートをデプロイの PR 本文にも使う。

- **前回のタグを明示している**（`previous_tag_name`）。省くと GitHub は前回の「Release」を起点にするので、
  Release を作っていない範囲があると起点がずれる（v1.0.1 までは Release を作っていない）
- `.github/release.yml` は、ノートを作る対象のコミット（タグの位置）から読まれる

### うまくいかないとき

- **デプロイの PR が出ない**: `create-k8s-pr` のログを見る。マニフェストの `image:` の行が書き換わらなかった
  （マニフェストの書式が変わった）ときは、わざと赤で止めている。検査が赤なら、そもそも `release` と
  `create-k8s-pr` は動かない
- **失敗した実行を作り直したい**: Actions の画面で、その実行を Re-run する（失敗したジョブだけでもよい）
- **Tag a release が「Nothing to release」で止まる**: 前回のタグから main にコミットが無い
