# Tasks: restructure-docs-layout

- [x] 1. `docs/` に `00_ホーム` 〜 `90_テンプレート` のフォルダーを作り、各フォルダーに入口のノート（`ホーム.md` など）を置く
- [x] 2. 既存の `getting-started.md` / `ci-cd.md` / `adding-targets.md` を `git mv` で `40_運用/` に移す
- [x] 3. `openspec/` を `git mv` で `docs/openspec/` に移し、直下に `openspec` → `docs/openspec` のシンボリックリンクを置く
- [x] 4. `docs/.obsidian/` に共有の設定（`app.json` / `templates.json`）を置き、個人の状態を `.gitignore` で除く
- [x] 5. `.gitignore` の `SPEC.md` を `/SPEC.md` にし、`openspec/**/spec.md` が無視されないようにする
- [x] 6. AGENTS.md・README.md・README_ja.md の構成図と `docs/` へのリンクを直す（README は日英をそろえる）
- [x] 7. `git grep` で古いパス（`docs/getting-started.md` など）が残っていないことを確認する（archive は除く）
- [x] 8. `openspec list` と `openspec validate --all --strict` が、リポジトリ直下と `docs/` の両方から通ることを確認する
