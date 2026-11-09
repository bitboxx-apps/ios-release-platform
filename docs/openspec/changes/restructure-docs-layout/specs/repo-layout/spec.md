## ADDED Requirements

### Requirement: Documentation layout
人間向けのドキュメントは SHALL `docs/` の下の、番号付きのフォルダー（`00_ホーム` / `10_全体像` / `20_ドメイン知識` / `30_機能の地図` / `40_運用` / `50_事故と教訓` / `60_用語集` / `90_テンプレート`）に置く。仕様（OpenSpec）の実体は SHALL `docs/openspec/` に置き、リポジトリ直下の `openspec` は MUST `docs/openspec` へのシンボリックリンクにする。各フォルダーには入口として、フォルダー名から番号を除いた名前のノート（例: `10_全体像/全体像.md`）を置く。ノートどうしのリンクは Obsidian の `[[...]]` で書き、`docs/` は Obsidian の Vault として開けるようにする。

#### Scenario: OpenSpec CLI from the repository root
- **WHEN** リポジトリ直下で `openspec list` を実行する
- **THEN** `docs/openspec/changes/` にある change が一覧に出る

#### Scenario: Finding a feature's spec
- **WHEN** 開発者が `docs/00_ホーム/ホーム.md` から読み始める
- **THEN** `30_機能の地図` を通して、機能ごとの OpenSpec の change / spec とコードの場所にたどり着ける

#### Scenario: Recording an incident
- **WHEN** 開発中に再発しそうな問題が起きて解決する
- **THEN** `90_テンプレート` のひな形を使って、`50_事故と教訓` に原因・対処・再発防止を書く

#### Scenario: New spec files are tracked
- **WHEN** macOS で `openspec/changes/<id>/specs/<capability>/spec.md` を新しく作る
- **THEN** そのファイルは `.gitignore` に無視されず、`git status` に出る
