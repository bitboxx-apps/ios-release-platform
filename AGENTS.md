# AGENTS.md

このリポジトリで作業する AI エージェント（Claude Code / Codex / Cursor など）と人間の開発者向けのガイドです。
**作業を始める前に必ず読んでください。** 詳細な背景は `README_ja.md` と `docs/` にあります。

---

## 0. TL;DR

- 実装の前に **必ず OpenSpec（`openspec/`）を先に更新** する。spec に無い挙動は実装しない。
- プロダクトコードは `apps/<platform>/`、リリース基盤は `release/<platform>/` に置く。**両者を混ぜない。**
- `release/` は「`.env` から全部を生成する」設計。**生成物を直接直さず、テンプレート/スクリプト側を直す。**
- 秘密情報（`.env.platform` / `.env.local` / `*.p8` / `*.p12` / 鍵）は **絶対にコミットしない・出力しない**。
- 証明書の破壊的操作（`match nuke`、証明書削除、キーローテーション）は **人間の明示指示なしに実行しない**。

---

## 1. リポジトリ構成

```
.
├── AGENTS.md                 # このファイル（CLAUDE.md からも参照）
├── openspec/                 # 仕様の正（Source of Truth）。実装より先に更新する
│   ├── config.yaml           #   OpenSpec 設定（プロジェクトの前提・成果物ルール）
│   ├── specs/<capability>/   #   現在の仕様（合意済み・実装済み）
│   └── changes/<change-id>/  #   変更提案（proposal / tasks / design / spec delta）
│
├── apps/                     # プロダクトコード（プラットフォームごとに 1 ディレクトリ）
│   ├── ios/                  #   iOS アプリ（bootstrap が Xcode プロジェクトを生成）
│   ├── web/                  #   （将来）Web アプリ
│   └── android/              #   （将来）Android アプリ
│
├── packages/                 # （将来）プラットフォーム横断の共有物
│                             #   例: API スキーマ(OpenAPI/proto)、デザイントークン、文言、共通ロジック
├── services/                 # （将来）バックエンド（例: チャットサーバー、Push 配信）
│
├── release/                  # リリース基盤（プラットフォームごと）
│   └── ios/                  #   bootstrap / scripts / fastlane / match / policies / config
│
├── .github/workflows/        # CI/CD。ファイル名は `<platform>-<purpose>.yml`
│   ├── ios-ci.yml            #   iOS: 署名なしビルド & テスト（paths フィルタ付き。bootstrap 前は skip）
│   └── ios-deploy.yml        #   iOS: 署名ビルド & TestFlight（タグ `v*` / `ios/v*`）
│
├── docs/                     # 人間向けドキュメント
└── .env.*.example            # 環境変数テンプレート（3 層構成）
```

### 依存方向のルール

| ディレクトリ | 置くもの | 依存してよい先 |
|---|---|---|
| `apps/<pf>/` | プロダクトコード・アセット | 自分自身、`packages/` |
| `packages/` | 共有コード・スキーマ・トークン | `packages/` 内のみ |
| `services/` | バックエンド | 自分自身、`packages/` |
| `release/<pf>/` | 署名・ビルド・配布ロジック | 環境変数のみ（`apps/` のコードを import しない） |
| `.github/workflows/` | ワークフロー定義 | `release/<pf>/` のスクリプト、`.env.app`、Secrets |

- `apps/<pf>/` に fastlane・署名・CI ロジックを置かない。
- `apps/ios/` と `apps/web/` が互いを直接参照しない。共有したいものは `packages/` に切り出す。

### 新しいプラットフォームを追加するとき（例: web）

1. **先に OpenSpec の change を作る**（§3 参照）。capability 例: `web-app`, `web-release`。
2. `apps/web/` にプロダクトコードを置く。
3. リリース基盤が必要なら `release/web/` を作り、`release/ios/` と同じ構成（`bootstrap/` `scripts/` `config/` `policies/`）に揃える。
4. ワークフローは `.github/workflows/web-ci.yml` / `web-deploy.yml` とし、`paths:` で `apps/web/**` `release/web/**` に絞る。
5. デプロイ用タグは `web/vX.Y.Z` のようにプラットフォームのプレフィックスを付ける（`v*` は iOS 用として残している）。
6. 新しく必要になった環境変数は `release/<pf>/config/env.schema.json` と `.env.*.example` に追加する。
7. この AGENTS.md の構成図と README を更新する。

---

## 2. リリース基盤（release/ios）の扱い方

### 2.1 設計の考え方（守ること）

| 原則 | 意味 | 実装時に気をつけること |
|---|---|---|
| **冪等性** | 何回実行しても同じ結果になる | 実行前に既存の状態を確認し、あればスキップする（`file_exists` などのヘルパーを使う） |
| **非対話** | `--init` のウィザード以外は入力を求めない | 値が足りなければ `[FAIL]` を出してすぐ終了する |
| **Fail-Fast** | 異常はその場で止める | スクリプトは `set -euo pipefail`。黙って続行しない |
| **生成型** | Xcode プロジェクトと fastlane 設定は `.env` から生成する | 生成物ではなく **テンプレート** を直す |
| **証明書の安全** | 破壊的操作は自動化しない | `release/ios/policies/signing-policy.md` に従う |

### 2.2 環境変数（3 層構成）

上の層が下の層を上書きします。

```
.env.platform  (最下位 — 組織の秘密情報, git-ignored)
.env.app       (中位   — アプリの識別情報, コミットする。秘密情報は入れない)
.env.local     (最上位 — 開発者ごとの上書き, git-ignored)
```

- 変数を追加・変更したら、**必ず** `release/ios/config/env.schema.json` と `.env.*.example` も直す。
- `.env.app` に `APP_NAME` が無い間（bootstrap 前）は、`ios-ci.yml` の macOS ビルドは skip される（失敗にはならない）。`.env.app` をコミットすると自動で有効になる。
- CI は `.env.app` から `APP_NAME` を読み、`APP_SCHEME` と `XCODE_PROJECT_PATH=apps/ios/${APP_NAME}.xcodeproj` を作る。
- 読み込みは `release/ios/scripts/ensure_idempotency.sh` の `load_env_layers` にまとまっている。独自の読み込み処理を書かない。

### 2.3 どこを直せばいいか

| やりたいこと | 直す場所 | 直してはいけない場所 |
|---|---|---|
| fastlane の lane やビルド設定を変える | `release/ios/platform/templates/Fastfile.template` | `release/ios/platform/fastlane/Fastfile`（生成物） |
| Appfile / Matchfile を変える | `release/ios/platform/templates/*.template` | 生成された `fastlane/` 配下 |
| 新規 Xcode プロジェクトの初期内容を変える | `release/ios/platform/templates/app/*` | — |
| 生成済みアプリの画面や機能を作る | `apps/ios/<APP_NAME>/` | `release/` 配下 |
| bootstrap の手順を増やす | `release/ios/bootstrap/bootstrap.sh` と、呼び出す `release/ios/scripts/*.sh` | — |
| 共通の処理（ログ、env、チェック） | `release/ios/scripts/ensure_idempotency.sh` | 各スクリプトに同じ処理をコピーしない |
| 環境変数を追加する | `env.schema.json` と `.env.*.example`、必要なら `bootstrap.ps1` | — |
| CI/CD を変える | `.github/workflows/ios-*.yml` | — |
| 署名・リリースのルールを変える | `release/ios/policies/*.md`（人間のレビュー必須） | — |

> テンプレートの `release/ios/platform/templates/app/` というディレクトリ名は「Xcode アプリのテンプレート」という意味です。リポジトリ直下の `apps/` とは別物です。

### 2.4 パスの規約

- スクリプトは `REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"` でリポジトリのルートを求める（`release/ios/<dir>/` から 3 階層上）。ディレクトリ構成を変えたら、ここも全部直す。
- リポジトリ内のパスは `REPO_ROOT` からの絶対パスで組み立てる。カレントディレクトリに頼らない。
- fastlane は `release/ios/platform` を作業ディレクトリとして実行される（`working-directory: release/ios/platform`）。

### 2.5 よく使うコマンド

```bash
./release/ios/bootstrap/doctor.sh            # 前提ツールの確認（何もインストールしない）
./release/ios/bootstrap/bootstrap.sh         # 検証のみ（何も変更しない）
./release/ios/bootstrap/bootstrap.sh --init  # 初回セットアップ（対話ウィザード・macOS 専用）
./release/ios/scripts/create_project.sh      # Xcode プロジェクトの生成（すでにあればスキップ）
./release/ios/scripts/deploy.sh [beta|release|test]  # ローカルで CI と同じ fastlane を実行
```

### 2.6 エージェントが実行してはいけないこと

- `bootstrap.sh --init`、`setup_secrets.sh`、`gh secret set`、`fastlane match`（readonly 以外）を **人間の指示なしに実行しない**（外部の状態が変わるため）。
- `match nuke`、証明書や Provisioning Profile の削除、API キーの作り直し。
- `.env.platform` / `.env.local` / `*.p8` / Secrets の値をログ・PR・コミットに出すこと。
- `deploy.sh` や TestFlight / App Store への配布を、指示なしに実行すること。

---

## 3. 実装の手順（OpenSpec を先に更新する）

**仕様（`openspec/`）が正です。** コードを先に書かないでください。

### 3.1 手順

1. **理解する**
   - `openspec/config.yaml` と、関係する `openspec/specs/<capability>/spec.md` を読む。
   - 進行中の変更を確認する: `openspec list`（CLI がない場合は `openspec/changes/` を見る）。
2. **提案（Proposal）を作る** — `openspec/changes/<change-id>/`
   - `<change-id>` は動詞から始まる kebab-case にする（例: `add-chat-message-list`、`update-ios-deploy-tags`）。
   - `proposal.md`: Why（なぜ）/ What Changes（何を変えるか）/ Impact（影響する spec・コード・運用）
   - `tasks.md`: 実装タスクのチェックリスト（テストとドキュメントの更新も含める）
   - `design.md`: 必要なときだけ書く（設計判断、プラットフォーム横断の変更、外部依存、セキュリティ・移行がある場合）
   - `specs/<capability>/spec.md`: 仕様の **差分（delta）**
     - `## ADDED Requirements` / `## MODIFIED Requirements` / `## REMOVED Requirements` / `## RENAMED Requirements`
     - 要件は `### Requirement: <名前>` と書き、本文に SHALL / MUST を使う
     - 各要件に `#### Scenario: <名前>` を **最低 1 つ** 付け、`- **WHEN** ...` / `- **THEN** ...` の形で書く
3. **検証する**: `openspec validate <change-id> --strict`
4. **合意を取る**: proposal を人間がレビューして OK を出すまで、実装に入らない（エージェントは提案を作ったところで一度止まる）。
5. **実装する**
   - `tasks.md` を上から順に進め、終わったものは `- [x]` にする。
   - spec に無い挙動を追加したくなったら、**先に spec delta を直す**。
6. **確認する**（§4 のチェックリスト）
7. **アーカイブする**: デプロイ・マージが終わったら `openspec archive <change-id> --yes`
   - delta が `openspec/specs/` に取り込まれ、change は `openspec/changes/archive/YYYY-MM-DD-<change-id>/` に移る。

### 3.2 提案が要らない変更

誤字の修正、コメントの修正、挙動が変わらないリファクタ、依存の patch 更新、既存の spec どおりにするバグ修正。
**それ以外**（新機能、挙動の変更、ディレクトリ構成の変更、CI/CD や署名まわりの変更、新しいプラットフォームの追加）は必ず提案を作る。

### 3.3 capability の分け方（目安）

| capability | 内容 |
|---|---|
| `repo-layout` | ディレクトリ構成と依存方向のルール |
| `ios-release` | iOS のリリース基盤（bootstrap / 署名 / CI / 配布） |
| `ios-app` / `web-app` / ... | 各プラットフォームのアプリの機能 |
| `<domain>` | プラットフォームをまたぐ機能（例: `chat-messaging`, `auth`）。各アプリはこの spec を参照する |

> OpenSpec CLI（v1 系）: `npm install -g @fission-ai/openspec` → `openspec init --tools <claude,codex,cursor...>` で、使っている AI ツール用のスラッシュコマンド（`/opsx:propose` → `/opsx:apply` → `/opsx:archive`）が入る。
> スラッシュコマンドを使う場合も、§3.1 の順番（提案 → 検証 → 合意 → 実装 → アーカイブ）は変わらない。

---

## 4. 完了前のチェックリスト

- [ ] OpenSpec の change があり、`openspec validate --strict` が通る（§3.2 の例外を除く）
- [ ] シェルスクリプト: `bash -n` と `shellcheck -S warning` で新しい警告が出ていない
- [ ] パスを変えたら `git grep` で古いパスが残っていないことを確認した
- [ ] 環境変数を変えたら `env.schema.json` と `.env.*.example` も更新した
- [ ] iOS: `ios-ci.yml` が通る（ローカルなら `xcodebuild build` を署名なしで実行）
- [ ] README / README_ja / docs / この AGENTS.md の、関係する部分を更新した
- [ ] 秘密情報が差分に入っていない

---

## 5. コーディング規約

- **Shell**: `#!/usr/bin/env bash` と `set -euo pipefail`。ログは `log_step` / `log_ok` / `log_warn` / `log_fail` を使う。変数は必ずクォートする。
- **Ruby (Fastfile)**: ENV の値は `sanitize_env_scalar` を通してから使う。秘密情報を `UI.message` などで出力しない。
- **Swift (apps/ios)**: SwiftUI を使う。`APP_NAME` は Swift の識別子なので、ハードコードせずに生成された名前に従う。
- **コミット**: 1 コミット 1 目的。OpenSpec の change に関するコミットは、本文に `<change-id>` を書く。
- **ドキュメントの言語**: README は日英の 2 つを同期させる。AGENTS.md と openspec は日本語でよい。

---

## 6. テンプレートとの関係

このリポジトリは `bitboxx-apps/ios-release-platform`（GitHub Template）から作られています。
テンプレートから作ったリポジトリは、元のテンプレートと **git の履歴を共有しません**。

- `release/` や AGENTS.md など **基盤側の改善** は、まず `ios-release-platform` に PR を出し、そのあと各アプリのリポジトリに同じ変更を反映する。
- `apps/` 配下と、アプリ固有の `openspec/specs/` はアプリのリポジトリだけで管理する。
