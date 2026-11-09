# Proposal: restructure-docs-layout

## Why
- `docs/` は英語の手順書が 3 つ並んでいるだけで、全体像・ドメイン知識・機能と仕様の対応・過去の失敗を書く場所が決まっていない。決まっていないと、知識がエージェントのメモリや PR の会話に散らばる。
- 仕様（`openspec/`）が `docs/` の外にあるため、ドキュメントを読む人が仕様にたどり着きにくい。
- 番号付きのフォルダーにそろえると、Obsidian などで開いたときの並び順が固定され、どこに何を書けばよいか迷わなくなる。
- この構成は `chat-app` で先に使い、運用できることを確かめた（同じ構成をテンプレート側にも入れる）。

## What Changes
- **BREAKING（パスの変更）** `docs/` を次の番号付きのフォルダーに分ける。
  | フォルダー | 書くこと |
  |---|---|
  | `00_ホーム/` | 入口（`ホーム.md`）。読む順番と、各フォルダーへのリンク |
  | `10_全体像/` | リポジトリとシステムの構成、環境変数の層、ビルドから配布までの流れ |
  | `20_ドメイン知識/` | アプリの概念とふるまい（アプリを作り始めたら書く） |
  | `30_機能の地図/` | 機能 → OpenSpec の change / spec → コードの場所、の対応表 |
  | `40_運用/` | 既存の `getting-started.md` / `ci-cd.md` / `adding-targets.md` と、よく使うコマンド |
  | `50_事故と教訓/` | 実際に起きた問題と、その原因・対処・再発防止（確認できた事実だけ） |
  | `60_用語集/` | 用語集 |
  | `90_テンプレート/` | 新しいノート・事故の記録・用語のひな形 |
  | `openspec/` | 仕様（下記） |
- **BREAKING（パスの変更）** `openspec/` の実体を `docs/openspec/` に移す。リポジトリ直下には `openspec` → `docs/openspec` のシンボリックリンクを置き、OpenSpec CLI・スラッシュコマンド・AGENTS.md の `openspec/...` という書き方はそのまま使えるようにする。
- `docs/` は Obsidian の Vault として開く前提にし、リンクは `[[...]]` で書く。各フォルダーの入口は、フォルダー名から番号を除いた名前のノート（`全体像.md` など）。
- Vault の共有設定（`docs/.obsidian/app.json`、`templates.json`）をコミットする。ウィンドウの状態など個人の設定は `.gitignore` で除く。
- 既存の 3 つの手順書は、中身を変えずに `40_運用/` に移す（英語のまま）。新しく書くドキュメントは日本語。
- AGENTS.md・README・README_ja の構成図と、`docs/` へのリンクを直す。完了前のチェックリストに、`30_機能の地図` と `50_事故と教訓` の更新を足す。
- `repo-layout` の spec に、ドキュメントの置き場所の要件を足す。

## やらないこと
- アプリ固有の中身（ドメイン知識・機能）は書かない。テンプレートから作った各アプリのリポジトリで書く。

## 移行手順
- パスを使っているもの: AGENTS.md、README.md、README_ja.md。
- `openspec` を直接開いていたツールは、シンボリックリンクのおかげで変更不要。Windows で `core.symlinks=false` の場合はリンクがテキストファイルになるため、`docs/openspec/` を直接使う（README に書く）。
- テンプレートから作った既存のアプリのリポジトリは、`git mv openspec docs/openspec && ln -s docs/openspec openspec` と、`docs/` の手順書の `git mv` で同じ構成にできる。

## Impact
- プラットフォーム: shared（ドキュメントとリポジトリ構成のみ。ios / web / android のコードは変えない）
- Spec: `repo-layout`（Documentation layout の要件を追加）
- Code: なし。`docs/`、`openspec/`、`.gitignore`、AGENTS.md、README.md、README_ja.md
- CI/CD: 変更なし（`ios-ci.yml` の `paths` に `docs/` は含まれていない）
- 運用: OpenSpec CLI はリポジトリ直下からも `docs/` からも動く。
