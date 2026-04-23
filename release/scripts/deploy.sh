#!/usr/bin/env bash
# release/scripts/deploy.sh — ローカルで CI 相当の fastlane ビルド・デプロイを実行する
#
# Usage:
#   ./release/scripts/deploy.sh [--run-number N] [beta|release|test]
#
# 環境変数は .env.platform → .env.app → .env.local の順で読み込み、
# 後から読んだファイルが優先（GitHub Actions の Secrets 相当はここで補完）。
#
# このスクリプトは ios-release-platform に同梱され、各アプリへ clone された
# 時点でそのまま利用可能。アプリ固有の値はすべて .env から読み込むため、
# スクリプト自体に編集は不要。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# release/scripts/ から見たアプリのルート（= リポジトリのルート）
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── ヘルプ ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [--run-number N] [lane]

ローカル Xcode を使って GitHub Actions 相当のビルド・デプロイを実行します。

Options:
  --run-number N   ビルド番号の基数を指定（build = N + 1000）
                   省略時は日時から自動生成
  --help, -h       このヘルプを表示

Lanes:
  beta     (デフォルト) ビルドして TestFlight にアップロード
  release  App Store 本番にアップロード
  test     テストのみ実行

Examples:
  ./release/scripts/deploy.sh
  ./release/scripts/deploy.sh --run-number 200
  ./release/scripts/deploy.sh release
EOF
}

# ── 引数パース ────────────────────────────────────────────────────────────────
LANE="beta"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-number)
            export GITHUB_RUN_NUMBER="$2"
            shift 2
            ;;
        --help|-h)
            usage; exit 0
            ;;
        beta|release|test)
            LANE="$1"; shift
            ;;
        *)
            echo "Error: 不明な引数 '$1'" >&2
            usage; exit 1
            ;;
    esac
done

# ── .env ファイルロード（後から読むほど優先）─────────────────────────────────
load_env_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]]          && continue
        [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
        export "$line"
    done < "$file"
    echo "  loaded: $file"
}

echo "▶ 環境変数を読み込み中..."
load_env_file "$REPO_ROOT/.env.platform"
load_env_file "$REPO_ROOT/.env.app"
load_env_file "$REPO_ROOT/.env.local"

# ── 必須チェック ──────────────────────────────────────────────────────────────
if [[ -z "${APP_NAME:-}" ]]; then
    echo "Error: APP_NAME が未設定です。.env.app を確認してください。" >&2
    exit 1
fi
if [[ -z "${MATCH_PASSWORD:-}" ]]; then
    echo "Error: MATCH_PASSWORD が未設定です。.env.platform を確認してください。" >&2
    exit 1
fi

# ── CI 互換の変数をセット ─────────────────────────────────────────────────────

# xcodebuild が使うプロジェクトパスを CI workflow と同じ形式で設定
export APP_SCHEME="$APP_NAME"
# 絶対パスで渡す: Fastfile の project_path_for_ci は start_with?("/") で早期 return するため
# GITHUB_WORKSPACE 未設定時の相対パス誤計算を回避できる
export XCODE_PROJECT_PATH="$REPO_ROOT/app/${APP_NAME}.xcodeproj"

# ASC キー: ローカルでは .p8 ファイルパスを直接 ASC_KEY_PATH_CI に渡す
# Fastfile は ASC_KEY_PATH_CI → ASC_KEY_CONTENT の順で試みるため、
# ローカルでは前者だけセットすれば ASC_KEY_CONTENT は不要。
if [[ -n "${ASC_KEY_PATH:-}" && -f "${ASC_KEY_PATH}" ]]; then
    export ASC_KEY_PATH_CI="$ASC_KEY_PATH"
    # Fastfile 内の asc_api_key_from_env が ASC_KEY_CONTENT を必須チェックするため
    # ファイルの内容を変数にも詰めておく
    export ASC_KEY_CONTENT
    ASC_KEY_CONTENT="$(cat "$ASC_KEY_PATH")"
    echo "  ASC key: $ASC_KEY_PATH"
elif [[ -z "${ASC_KEY_CONTENT:-}" ]]; then
    echo "Error: ASC_KEY_PATH が見つからず ASC_KEY_CONTENT も未設定です。" >&2
    echo "       .env.app に ASC_KEY_PATH=/path/to/AuthKey_XXXXXX.p8 を設定してください。" >&2
    exit 1
fi

# match SSH キー: ローカルではファイルパスから内容を読んで MATCH_GIT_PRIVATE_KEY に渡す
if [[ -n "${MATCH_GIT_PRIVATE_KEY_PATH:-}" && -f "${MATCH_GIT_PRIVATE_KEY_PATH}" ]]; then
    export MATCH_GIT_PRIVATE_KEY
    MATCH_GIT_PRIVATE_KEY="$(cat "$MATCH_GIT_PRIVATE_KEY_PATH")"
    echo "  match SSH key: $MATCH_GIT_PRIVATE_KEY_PATH"
fi

# ビルド番号: 未指定なら MMDDHHmm 形式の日時から生成
# build number = GITHUB_RUN_NUMBER + 1000 (Fastfile の仕様)
if [[ -z "${GITHUB_RUN_NUMBER:-}" ]]; then
    GITHUB_RUN_NUMBER="$(date '+%m%d%H%M')"
    export GITHUB_RUN_NUMBER
fi
BUILD_NUMBER=$((10#${GITHUB_RUN_NUMBER} + 1000))

# ── 実行サマリー ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " App         : $APP_NAME"
echo " Project     : $XCODE_PROJECT_PATH"
echo " Xcode       : $(xcodebuild -version | head -1)"
echo " Lane        : $LANE"
echo " Build #     : $BUILD_NUMBER  (run_number=$GITHUB_RUN_NUMBER)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── fastlane 実行 ─────────────────────────────────────────────────────────────
cd "$REPO_ROOT/release/platform"
bundle install --quiet
bundle exec fastlane "$LANE"
