# repo-layout Specification

## Purpose
複数プラットフォーム（iOS / Web / Android など）が同じリポジトリで並存できるように、ディレクトリ構成と依存方向を定める。

## Requirements

### Requirement: Platform-scoped product code
プロダクトコードは SHALL `apps/<platform>/` に置く。iOS アプリは `apps/ios/` に置く。

#### Scenario: iOS project generation
- **WHEN** `release/ios/scripts/create_project.sh` を `APP_NAME=ChatApp` で実行する
- **THEN** `apps/ios/ChatApp.xcodeproj` と `apps/ios/ChatApp/` が生成される

### Requirement: Platform-scoped release infrastructure
リリース基盤は SHALL `release/<platform>/` に置く。基盤は `apps/` のコードに依存しては MUST NOT（環境変数を通してのみやり取りする）。

#### Scenario: Repo root resolution
- **WHEN** `release/ios/<dir>/` 配下のスクリプトを任意のカレントディレクトリから実行する
- **THEN** `REPO_ROOT` はリポジトリのルートになる

### Requirement: Platform-prefixed workflows
GitHub Actions のワークフローは SHALL `<platform>-<purpose>.yml` という名前にし、CI は `paths` フィルタで該当プラットフォームの変更があったときだけ動かす。

#### Scenario: Web-only change
- **WHEN** `apps/web/` だけを変更して main に push する
- **THEN** `ios-ci.yml` は実行されない

#### Scenario: iOS tagged deploy
- **WHEN** `v1.2.0` または `ios/v1.2.0` のタグを push する
- **THEN** `ios-deploy.yml` が実行される

### Requirement: Shared code location
プラットフォームをまたいで共有するコード・スキーマ・デザイントークンは SHALL `packages/` に置き、`apps/<platform>/` 同士が直接参照し合っては MUST NOT。

#### Scenario: Sharing an API schema
- **WHEN** iOS と Web が同じ API スキーマを使う
- **THEN** スキーマは `packages/` に置かれ、両方のアプリはそこを参照する
