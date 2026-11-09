# Change: restructure-multi-platform-layout

## Why
`app/` と `release/` が iOS 専用の前提で、リポジトリ直下に固定されていた。Web や Android を追加するとき、置き場所とリリース基盤の分け方が決まっていなかった。

## What Changes
- `app/` → `apps/ios/`、`release/{bootstrap,config,platform,policies,scripts}` → `release/ios/...` に移動
- スクリプトの `REPO_ROOT` の求め方を 3 階層上に変更し、`.ps1` も同様に変更
- `ci.yml` / `deploy.yml` → `ios-ci.yml` / `ios-deploy.yml` に名前を変更。CI に `paths` フィルタを追加し、deploy で `ios/v*` タグも受け付けるようにした
- `ios-ci.yml` に preflight ジョブを追加。bootstrap 前（`.env.app` に `APP_NAME` が無い）は macOS ビルドを skip する。手動実行（`workflow_dispatch`）にも対応
- Fastfile の `project_path_for_ci` のフォールバックパスを修正（もとの `__dir__` 基準のパスは `release/app/...` を指していた不具合も合わせて修正）
- AGENTS.md / CLAUDE.md / openspec の雛形を追加し、README / docs のパスを更新
- **BREAKING**: すでに bootstrap 済みのリポジトリは、`app/` を `apps/ios/` に、`release/platform/fastlane/` を `release/ios/platform/fastlane/` に移す必要がある

## Impact
- Specs: `repo-layout`（新規）
- Code: `release/ios/**`, `.github/workflows/*`, `.gitignore`, README*, docs/*
- 確認したこと: `bash -n`、shellcheck（警告は増えていない）、Linux 上で `create_project.sh` を実行し、生成物が移行前と完全に一致することを確認、`doctor.sh` と env schema の解決を確認
- 未確認: macOS 上の xcodebuild と fastlane（PR の CI で確認する）
