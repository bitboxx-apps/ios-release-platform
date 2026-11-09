# Design: restructure-docs-layout

## openspec をどこに置くか
| 案 | 良いところ | 困るところ |
|---|---|---|
| A. 実体を `docs/openspec/`、直下に `openspec` のリンク（採用） | Vault の中で仕様が普通のフォルダーとして見え、`[[...]]` でリンクできる。CLI・AGENTS.md のパスは変わらない | Windows でシンボリックリンクが無効だとリンクが壊れる |
| B. 実体は直下のまま、`docs/openspec` をリンクにする | 何も壊れない | Obsidian などはリンク先のフォルダーを読まない・二重に索引することがある |
| C. 実体を移してリンクを置かない | 単純 | OpenSpec CLI はカレントディレクトリの `openspec/` を探すため、リポジトリ直下で動かなくなる |

OpenSpec CLI 1.3.1 で、A の構成のまま `openspec list` と `openspec validate --strict` が、リポジトリ直下と `docs/` の両方から動くことを確認した。

## ファイル名
- フォルダー名は `NN_日本語名`。番号は 10 刻みにし、あとから間に足せるようにする。
- 各フォルダーの入口は、フォルダー名から番号を除いた名前のノート（`10_全体像/全体像.md` など）にする。各フォルダーに `README.md` を置くと、`[[README]]` の行き先が決まらなくなるため。
- OpenSpec の `proposal.md` / `tasks.md` / `spec.md` は名前が重なるので、Vault の根からのパスで書く（`[[openspec/changes/<id>/proposal|<id>]]`）。ひな形やノートにこれらと同じ名前を付けない。

## Obsidian の設定
- コミットするのは、全員でそろえたい設定だけ: `app.json`（`[[...]]` 形式のリンク、リネーム時のリンク更新、アーカイブ済みの change を検索から除く）と `templates.json`（ひな形のフォルダー）。
- `workspace*.json`（開いているタブなど）と `cache` は個人の状態なので `.gitignore` で除く。
- コアプラグインの有効・無効（`core-plugins.json`）は Obsidian のバージョンで形式が変わるため、コミットしない。テンプレートのプラグインは各自で有効にする（`90_テンプレート/テンプレート.md` に書く）。

## `.gitignore` の `SPEC.md`
- 既存の `SPEC.md` の行は、macOS（`core.ignorecase=true`）では `openspec/**/spec.md` にも当たり、新しい spec が無視されていた。リポジトリ直下だけを除く `/SPEC.md` に直す（既存の挙動の意図どおりにするバグ修正）。
