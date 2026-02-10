#!/usr/bin/env bash
# setup_secrets.sh — Provision GitHub secrets using gh CLI
# Checks for existence before creation. Secrets are never echoed.
# ASC key is base64-encoded before upload. SSH key is uploaded as-is.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ensure_idempotency.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load environment
load_env_layers "$REPO_ROOT"

require_command "gh" "Install GitHub CLI: https://cli.github.com/"

log_step "Provisioning GitHub secrets"

# Determine repository
REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
fi

if [[ -z "$REPO" ]]; then
    log_fail "Cannot determine GitHub repository. Set GITHUB_REPOSITORY or ensure gh is authenticated."
    exit 1
fi

log_info "Target repository: ${REPO}"

set_secret() {
    local name="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        log_warn "Skipping ${name} — value is empty"
        return
    fi

    if secret_exists "$name" "$REPO"; then
        log_ok "${name} already exists — skipping"
    else
        echo "$value" | gh secret set "$name" --repo "$REPO" --body -
        log_ok "${name} provisioned"
    fi
}

# --- Required secrets ---
set_secret "MATCH_GIT_URL" "${MATCH_GIT_URL:-}"
set_secret "MATCH_PASSWORD" "${MATCH_PASSWORD:-}"
set_secret "APPLE_TEAM_ID" "${APPLE_TEAM_ID:-}"
set_secret "APP_BUNDLE_ID" "${APP_BUNDLE_ID:-}"

# --- ASC API Key (base64-encoded) ---
set_secret "ASC_KEY_ID" "${ASC_KEY_ID:-}"
set_secret "ASC_ISSUER_ID" "${ASC_ISSUER_ID:-}"

if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    if file_exists "${ASC_KEY_PATH}"; then
        if secret_exists "ASC_KEY_CONTENT" "$REPO"; then
            log_ok "ASC_KEY_CONTENT already exists — skipping"
        else
            ASC_KEY_BASE64=$(base64 < "${ASC_KEY_PATH}" | tr -d '\n')
            echo "$ASC_KEY_BASE64" | gh secret set "ASC_KEY_CONTENT" --repo "$REPO" --body -
            log_ok "ASC_KEY_CONTENT provisioned (base64-encoded from ${ASC_KEY_PATH})"
        fi
    else
        log_warn "ASC_KEY_PATH set but file not found: ${ASC_KEY_PATH}"
    fi
fi

# --- Match SSH key ---
if [[ -n "${MATCH_GIT_PRIVATE_KEY_PATH:-}" ]]; then
    if file_exists "${MATCH_GIT_PRIVATE_KEY_PATH}"; then
        if secret_exists "MATCH_GIT_PRIVATE_KEY" "$REPO"; then
            log_ok "MATCH_GIT_PRIVATE_KEY already exists — skipping"
        else
            gh secret set "MATCH_GIT_PRIVATE_KEY" --repo "$REPO" < "${MATCH_GIT_PRIVATE_KEY_PATH}"
            log_ok "MATCH_GIT_PRIVATE_KEY provisioned from ${MATCH_GIT_PRIVATE_KEY_PATH}"
        fi
    else
        log_warn "MATCH_GIT_PRIVATE_KEY_PATH set but file not found: ${MATCH_GIT_PRIVATE_KEY_PATH}"
    fi
fi

log_ok "GitHub secrets provisioning complete"
