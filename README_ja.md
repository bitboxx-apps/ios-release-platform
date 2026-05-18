# iOS Release Platform

> **[English version (README.md)](README.md)**

環境変数だけで **ビルド可能な Xcode プロジェクト** と **本番用リリースパイプライン** を生成する GitHub テンプレートです。

クローン → `.env` を埋める → コマンド1つ → CI で署名付きビルド & TestFlight デプロイ。

---

## なぜこのテンプレートがあるのか

iOS アプリを App Store に出すには、Xcode の署名設定、証明書管理、CI パイプライン、App Store Connect 認証情報の連携が必要です。多くのチームはこれをアドホックに構築し、メンバー変更や証明書の期限切れで壊れる脆い仕組みになりがちです。

このテンプレートは、リリースインフラを後付けではなく**最初から一級市民として扱います**。

**得られるもの:**

- `.env` の値から生成される Xcode プロジェクト — バンドルID、チーム、表示名、手動署名が最初から正しい
- fastlane match によるゼロタッチ証明書管理
- GitHub Actions によるビルド、署名、TestFlight デプロイ
- 1つの bootstrap コマンドですべてをプロビジョニング
- JSON Schema によるレイヤー型の環境設定バリデーション
- プロダクトコード (`app/`) とインフラ (`release/`) の明確な分離

**やらないこと:**

- 対話的ウィザードや暗黙のデフォルト
- システム依存関係の自動インストール
- 暗黙の証明書ローテーション
- 状態を黙って変更する一切の処理

---

## クイックスタート

### あなたが手でやることは1つだけ

[App Store Connect](https://appstoreconnect.apple.com/) で **API キーを払い出して 5 つのことをする** だけ:

1. **Users and Access → Integrations → App Store Connect API → Team Keys** で `+` → Role: **Admin** で発行
2. `AuthKey_XXXXXXXXXX.p8` をダウンロード(ローカルに保存)
3. 控える: **Key ID**(10文字英数字)、**Issuer ID**(UUID)
4. **Membership** ページから **Team ID**(10文字英数字)
5. Developer Portal で **Bundle ID** を Explicit 登録 + App Store Connect で **App レコード**を作成

### 残り全部はワンコマンド

```bash
./release/bootstrap/bootstrap.sh --init
```

対話 wizard が立ち上がるので、上の 4 値を入力するだけ。

| 入力 | 内容 |
|---|---|
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` | 発行した API キー |
| `APPLE_TEAM_ID` | Membership ページの Team ID |
| Bundle ID | **`1) 維持` / `2) 自動生成` / `3) 手動入力`** から選ぶ |
| Match 署名リポジトリ | **`1) デフォルト名で自動作成` / `2) 既存 URL` / `3) 指定名で自動作成`** から選ぶ |

wizard が以下を自動で行います:

- **署名用プライベートリポジトリ**を `gh repo create` で作成(or 既存を再利用)
- **SSH デプロイキー**を生成し、signing repo の Deploy keys に登録
- **MATCH_PASSWORD** を `openssl rand` で生成(signing repo が既存内容を持つ場合は既存パスを入力プロンプト)
- `.env.local` に上記をすべて保存
- 続けて bootstrap.sh が:
  - Xcode プロジェクトの Team ID / Bundle ID / Manual 署名を解決
  - `fastlane match` で証明書とプロビジョニングプロファイル生成 → signing repo に push
  - GitHub Secrets を `gh secret set` で投入
  - Fastfile / Appfile / Matchfile を生成

### コミット & デプロイ

```bash
git add .env.app app/ release/platform/fastlane/
git commit -m "Initialize release infrastructure"
git push origin main
```

push と同時に `.github/workflows/deploy.yml` が走り、約 6〜10 分で TestFlight の Processing 状態まで自動で進みます。

`v*` タグでも別途デプロイをキックできます:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 環境チェック(任意)

```bash
./release/bootstrap/doctor.sh
```

Doctor は前提条件を検証しますが、インストールは行いません。

---

## リポジトリ構成

```
.
├── app/                              # プロダクトコード — bootstrap で生成
│   ├── <APP_NAME>.xcodeproj/         #   Xcode プロジェクト（手動署名、正しいチーム/バンドルID）
│   └── <APP_NAME>/                   #   Swift ソース、アセット
│
├── release/                          # リリースインフラ — app/ には触れない
│   ├── bootstrap/
│   │   ├── doctor.sh                 #   環境バリデーター
│   │   ├── bootstrap.sh              #   プライマリイニシャライザ (macOS)
│   │   └── bootstrap.ps1             #   シークレットプロビジョニング (Windows)
│   ├── scripts/
│   │   ├── create_project.sh         #   テンプレートから Xcode プロジェクト生成
│   │   ├── ensure_idempotency.sh     #   共有ヘルパー（ログ、env、チェック）
│   │   ├── setup_ruby.sh             #   Ruby バージョン検証
│   │   ├── setup_fastlane.sh         #   fastlane の条件付きインストール
│   │   ├── setup_match.sh            #   証明書同期（readonly/init）
│   │   └── setup_secrets.sh          #   GitHub Secrets プロビジョニング
│   ├── platform/
│   │   ├── fastlane/                 #   生成された fastlane 設定
│   │   ├── templates/                #   Fastfile, Appfile, Matchfile, Xcode テンプレート
│   │   ├── signing/                  #   署名成果物
│   │   └── Gemfile                   #   Ruby 依存関係
│   ├── policies/
│   │   ├── signing-policy.md         #   証明書ガバナンスルール
│   │   └── release-policy.md         #   リリースパイプラインルール
│   └── config/
│       └── env.schema.json           #   環境バリデーションスキーマ
│
├── .github/workflows/
│   ├── ci.yml                        #   push/PR 時のビルド & テスト（署名なし）
│   └── deploy.yml                    #   v* タグで署名ビルド & TestFlight
│
├── docs/                             #   ドキュメント
├── .env.platform.example             #   組織レベル設定テンプレート
├── .env.app.example                  #   アプリ固有設定テンプレート（コミット対象）
└── .env.local.example                #   開発者オーバーライドテンプレート（git-ignored）
```

### 関心の分離

| ディレクトリ | 内容 | 依存先 |
|-------------|------|--------|
| `app/` | プロダクトコード、Xcode プロジェクト、アセット | `app/` 外には依存しない |
| `release/` | 署名、fastlane、bootstrap、CI ロジック | 環境変数のみ |
| `.github/` | ワークフロー定義 | `release/` スクリプト、`.env.app`、シークレット |

fastlane、署名、CI、bootstrap のロジックは **絶対に** `app/` 内に置きません。

---

## 環境モデル

設定は3層システムを使用。各層は前の層を上書きします:

```
.env.platform    (最低優先 — 組織の秘密情報、git-ignored)
.env.app         (中間     — アプリ識別情報、コミット対象)
.env.local       (最高優先 — 開発者オーバーライド、git-ignored)
```

`.env.app` はシークレットを含まないため、リポジトリにコミットします。CI が `APP_NAME` をビルドに使用するためです。

### 必須変数

| 変数 | 説明 | 例 |
|------|------|-----|
| `APPLE_TEAM_ID` | Apple Developer Team ID (10文字) | `A1B2C3D4E5` |
| `MATCH_GIT_URL` | 署名リポジトリ URL (SSH 推奨) | `git@github.com:org/certs.git` |
| `MATCH_PASSWORD` | Match 暗号化パスフレーズ | *(secret)* |
| `APP_BUNDLE_ID` | バンドル識別子 (逆DNS) | `com.company.myapp` |
| `APP_NAME` | Xcode プロジェクト名 (スペース不可) | `MyApp` |
| `APP_DISPLAY_NAME` | ホーム画面の表示名 (スペースOK) | `My App` |

### オプション変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `MATCH_TYPE` | 署名タイプ | `appstore` |
| `ASC_KEY_ID` | App Store Connect API Key ID | — |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID | — |
| `ASC_KEY_PATH` | `.p8` キーファイルのローカルパス | — |
| `APPLE_ID` | fastlane/match が Apple Developer Portal にアクセスするための Apple ID メールアドレス（.env.local 推奨） | — |
| `MATCH_GIT_PRIVATE_KEY_PATH` | match リポジトリ用 SSH キーのローカルパス | — |

`APP_SCHEME` と `XCODE_PROJECT_PATH` は `APP_NAME` から自動導出されます。

---

## CI/CD

### CI — プッシュ & PR ごと (`ci.yml`)

署名なしでビルド & テスト。誰でもビルドが通ることを確認できます。

### Deploy — バージョンタグ (`deploy.yml`)

```bash
git tag v1.2.0
git push origin v1.2.0
```

パイプライン:
1. コミット済みの `.env.app` から `APP_NAME` を読み取り
2. Ruby + bundler をキャッシュ付きでセットアップ
3. `fastlane beta` を実行: match 同期 → ビルド → TestFlight アップロード

ビルド番号は `GITHUB_RUN_NUMBER + 1000` オフセットで自動インクリメントされます。

### 必要な GitHub Secrets

`bootstrap.sh --init` により自動プロビジョニング:

| Secret | ソース | 説明 |
|--------|--------|------|
| `MATCH_GIT_URL` | `.env.platform` | 署名リポジトリ URL |
| `MATCH_PASSWORD` | `.env.platform` | Match 暗号化パスフレーズ |
| `MATCH_GIT_PRIVATE_KEY` | SSH キーファイル | 署名リポジトリへの SSH アクセス |
| `APPLE_TEAM_ID` | `.env.platform` | Apple Developer Team ID |
| `APP_BUNDLE_ID` | `.env.app` | バンドル識別子 |
| `ASC_KEY_ID` | `.env.app` | App Store Connect Key ID |
| `ASC_ISSUER_ID` | `.env.app` | App Store Connect Issuer ID |
| `ASC_KEY_CONTENT` | `.p8` ファイル (base64) | App Store Connect 秘密鍵 |

---

## Bootstrap モード

### Init モード (`--init`)

リポジトリごとに1回実行(対話 wizard あり):

```
bootstrap.sh --init
  ├── 対話 wizard (auto_provision.sh)
  │     ├── ASC API キー入力 (Key ID / Issuer ID / .p8 パス)
  │     ├── Apple Team ID 入力
  │     ├── Bundle ID — 維持 / 自動生成 / 手動入力 を選択
  │     ├── 署名リポジトリ — デフォルト名で自動作成 / 既存 URL / 指定名で自動作成 を選択
  │     ├── SSH デプロイキー — 自動生成 + 公開鍵を Deploy keys に登録
  │     └── MATCH_PASSWORD — 自動生成(repo 既存内容ありの場合は既存パスを要求)
  ├── env をスキーマに対してバリデーション
  ├── テンプレートから Xcode プロジェクト生成 / pbxproj 内のプレースホルダを解決
  ├── Ruby >= 3.2 + fastlane を検証
  ├── fastlane 設定を生成 (Fastfile, Appfile, Matchfile)
  ├── match で証明書を生成
  ├── GitHub Secrets をプロビジョニング (base64 ASC キー, SSH match キー)
  └── 署名アクセスを検証 (readonly 同期)
```

wizard は **冪等**で、`.env.local` に既に値があれば再質問しません。安全に再実行可能。

### 通常モード (デフォルト)

状態を変更せずにバリデーション:

```
bootstrap.sh
  ├── env をスキーマに対してバリデーション
  ├── Xcode プロジェクトの存在を確認
  ├── Ruby >= 3.2 + fastlane を検証
  ├── GitHub Secrets の存在を確認
  └── match を readonly モードで実行
```

---

## プラットフォーム規約

### 冪等性

すべてのスクリプトは実行前に既存の状態をチェックします。どのコマンドも2回実行して同じ結果になります。

### 非対話実行

スクリプトは一切入力を求めません。値が不足している場合は明確なエラーを出して終了します。

### フェイルファスト

環境変数の不足、非対応 OS、スキーマ違反は即座に停止:

```
[FAIL] Required variable missing: APPLE_TEAM_ID
[FAIL] Environment validation failed — check .env files
```

### 証明書の安全性

破壊的な操作 (`match nuke`、証明書削除、キーローテーション) は**自動では絶対に実行されません**。`release/policies/signing-policy.md` を参照してください。

---

## Windows サポート

Windows は**シークレットのプロビジョニングと設定のみ**に対応:

```powershell
.\release\bootstrap\bootstrap.ps1 -Init
```

iOS のビルド操作には macOS が必要です。

---

## 前提条件

| 依存関係 | 最低バージョン | インストール |
|----------|-------------|-------------|
| Ruby | 3.2 | `rbenv install 3.3.0` |
| Bundler | any | `gem install bundler` |
| fastlane | any | `bundle install` |
| Git | any | システムパッケージマネージャ |
| GitHub CLI | any | [cli.github.com](https://cli.github.com/) |
| OpenSSL | any | システムパッケージマネージャ |
| Xcode | 15+ | Mac App Store |

---

## 設計上の判断

**なぜ事前ビルド済みではなく Xcode プロジェクトを生成するのか?**
事前ビルド済みのプロジェクトにはプレースホルダー値 (バンドルID、チーム、表示名) が入っており、Xcode の General タブで手動編集が必要です。`.env` の値からプロジェクトを生成することで、最初の `open *.xcodeproj` からすべてが正しい状態になります。

**なぜ `APP_NAME` と `APP_DISPLAY_NAME` を分けるのか?**
`APP_NAME` は Swift の識別子 (`struct MyAppApp: App`)、ディレクトリ名、Xcode ターゲット名に使われ、スペースを含められません。`APP_DISPLAY_NAME` はホーム画面に表示されるユーザー向けの名前で、何でも設定できます。

**なぜ ASC キーを base64 エンコードするのか?**
GitHub Actions のシークレットは文字列です。`.p8` ファイルはバイナリに近い形式です。TestFlight デプロイに成功した実績のあるプロジェクトでは、fastlane の `is_key_content_base64: true` で base64 エンコード済みの `ASC_KEY_CONTENT` を使用しています。

**なぜ match に HTTPS でなく SSH キーを使うのか?**
SSH キーによる署名リポジトリへのアクセスは CI 環境でより信頼性が高く、git 認証情報の保存が不要です。

---

## ライセンス

MIT
