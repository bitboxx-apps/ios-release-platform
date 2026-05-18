#!/usr/bin/env bash
# setup_match.sh — Initialize match in readonly mode
# Never regenerates certificates automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ensure_idempotency.sh"

require_macos

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FASTLANE_DIR="${REPO_ROOT}/release/platform/fastlane"

# Load environment
load_env_layers "$REPO_ROOT"

require_var "MATCH_GIT_URL"
require_var "MATCH_PASSWORD"
require_var "APPLE_TEAM_ID"
require_var "APP_BUNDLE_ID"
require_var "MATCH_TYPE"

export MATCH_PASSWORD
export FASTLANE_TEAM_ID="${FASTLANE_TEAM_ID:-$APPLE_TEAM_ID}"

# If APPLE_ID is provided, pass it through to fastlane match to avoid ambiguity.
if [[ -n "${APPLE_ID:-}" ]]; then
    export FASTLANE_USER="${FASTLANE_USER:-$APPLE_ID}"
fi

# If a deploy key path is provided, explicitly pass it to match.
# Otherwise match will fall back to whatever ssh-agent/default key provides.
GIT_PRIVATE_KEY_ARGS=()
if [[ -n "${MATCH_GIT_PRIVATE_KEY_PATH:-}" ]]; then
    if file_exists "${MATCH_GIT_PRIVATE_KEY_PATH}"; then
        GIT_PRIVATE_KEY_ARGS=(--git_private_key "${MATCH_GIT_PRIVATE_KEY_PATH}")
    else
        log_warn "MATCH_GIT_PRIVATE_KEY_PATH set but file not found: ${MATCH_GIT_PRIVATE_KEY_PATH}"
    fi
fi

# Build an App Store Connect API key JSON file and pass it to fastlane
# match. Without this, match falls back to Apple-ID auth (interactive,
# 2FA, won't work in CI) when it needs to talk to the Developer Portal.
API_KEY_ARGS=()
API_KEY_JSON_PATH=""
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
    ASC_KEY_PATH_EXPANDED="${ASC_KEY_PATH/#\~/$HOME}"
    if [[ -f "$ASC_KEY_PATH_EXPANDED" ]]; then
        API_KEY_JSON_PATH="$(mktemp -t match_api_key.XXXXXX)"
        trap '[[ -n "$API_KEY_JSON_PATH" ]] && rm -f "$API_KEY_JSON_PATH"' EXIT
        python3 - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH_EXPANDED" "$API_KEY_JSON_PATH" <<'PY'
import json, sys
key_id, issuer_id, key_filepath, out_path = sys.argv[1:5]
payload = {
    "key_id": key_id,
    "issuer_id": issuer_id,
    "key_filepath": key_filepath,
    "in_house": False
}
with open(out_path, "w") as f:
    json.dump(payload, f)
PY
        API_KEY_ARGS=(--api_key_path "$API_KEY_JSON_PATH")
    else
        log_warn "ASC_KEY_PATH set but file not found: ${ASC_KEY_PATH}"
    fi
fi

READONLY="${1:-true}"
INIT_MODE="${2:-false}"

log_step "Setting up match (readonly=${READONLY})"

# Generate Matchfile if absent
MATCHFILE="${FASTLANE_DIR}/Matchfile"
if ! file_exists "$MATCHFILE"; then
    log_info "Generating Matchfile"
    mkdir -p "$FASTLANE_DIR"
    MATCH_STORAGE="${MATCH_STORAGE_MODE:-git}"
    cat > "$MATCHFILE" << MATCHEOF
git_url("${MATCH_GIT_URL}")
storage_mode("${MATCH_STORAGE}")
type("${MATCH_TYPE}")
app_identifier("${APP_BUNDLE_ID}")
readonly(true)
MATCHEOF
    log_ok "Matchfile generated at ${MATCHFILE}"
else
    log_ok "Matchfile already exists — skipping generation"
fi

run_match_command() {
    local readonly_value="$1"
    cd "$FASTLANE_DIR/.."
    local match_cmd=(
        bundle exec fastlane match "$MATCH_TYPE"
        --git_url "$MATCH_GIT_URL"
        --app_identifier "$APP_BUNDLE_ID"
        --team_id "$APPLE_TEAM_ID"
    )
    if [[ -n "${APPLE_ID:-}" ]]; then
        match_cmd+=(--username "$APPLE_ID")
    fi
    if (( ${#GIT_PRIVATE_KEY_ARGS[@]} )); then
        match_cmd+=("${GIT_PRIVATE_KEY_ARGS[@]}")
    fi
    if (( ${#API_KEY_ARGS[@]} )); then
        match_cmd+=("${API_KEY_ARGS[@]}")
    fi
    match_cmd+=(--readonly "$readonly_value")
    "${match_cmd[@]}"
}

if [[ "$INIT_MODE" == "true" ]]; then
    log_step "Running match in init mode (generating certificates)"
    run_match_command false
    log_ok "Match certificates generated"
else
    log_step "Running match in readonly mode"
    run_match_command true
    log_ok "Match readonly sync complete"
fi
