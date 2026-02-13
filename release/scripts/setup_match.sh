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

if [[ "$INIT_MODE" == "true" ]]; then
    log_step "Running match in init mode (generating certificates)"
    cd "$FASTLANE_DIR/.."
    bundle exec fastlane match "$MATCH_TYPE" \
        --git_url "$MATCH_GIT_URL" \
        --app_identifier "$APP_BUNDLE_ID" \
        --team_id "$APPLE_TEAM_ID" \
        ${APPLE_ID:+--username "$APPLE_ID"} \
        "${GIT_PRIVATE_KEY_ARGS[@]}" \
        --readonly false
    log_ok "Match certificates generated"
else
    log_step "Running match in readonly mode"
    cd "$FASTLANE_DIR/.."
    bundle exec fastlane match "$MATCH_TYPE" \
        --git_url "$MATCH_GIT_URL" \
        --app_identifier "$APP_BUNDLE_ID" \
        --team_id "$APPLE_TEAM_ID" \
        ${APPLE_ID:+--username "$APPLE_ID"} \
        "${GIT_PRIVATE_KEY_ARGS[@]}" \
        --readonly true
    log_ok "Match readonly sync complete"
fi
