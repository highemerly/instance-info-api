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
