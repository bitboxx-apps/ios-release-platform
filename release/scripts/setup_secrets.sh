#!/usr/bin/env bash
# setup_secrets.sh — Provision GitHub secrets using gh CLI
# Checks for existence before creation. Secrets are never echoed.
# ASC key is uploaded as base64 content (.p8). SSH key is uploaded as-is.

set -euo pipefail

FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        --help|-h)
            echo "Usage: setup_secrets.sh [--force]"
            echo ""
            echo "  --force    Overwrite existing GitHub Secrets"
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            exit 1
            ;;
    esac
done

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

expand_path() {
    local raw_path="$1"
    if [[ "$raw_path" == "~/"* ]]; then
        echo "${HOME}/${raw_path#~/}"
    else
        echo "$raw_path"
    fi
}

set_secret() {
    local name="$1"
    local value="$2"
    value="${value%$'\r'}"

    if [[ -z "$value" ]]; then
        log_warn "Skipping ${name} — value is empty"
        return
    fi

    if secret_exists "$name" "$REPO" && ! $FORCE; then
        log_ok "${name} already exists — skipping"
    else
        echo "$value" | gh secret set "$name" --repo "$REPO" --body -
        if $FORCE; then
            log_ok "${name} overwritten"
        else
            log_ok "${name} provisioned"
        fi
    fi
}

set_required_secret() {
    local name="$1"
    local value="$2"
    value="${value%$'\r'}"

    if [[ -z "$value" ]]; then
        log_fail "Required secret ${name} is empty"
        exit 1
    fi

    set_secret "$name" "$value"
}

# --- Required secrets ---
set_required_secret "MATCH_GIT_URL" "${MATCH_GIT_URL:-}"
set_required_secret "MATCH_PASSWORD" "${MATCH_PASSWORD:-}"
set_required_secret "APPLE_TEAM_ID" "${APPLE_TEAM_ID:-}"
set_required_secret "APP_BUNDLE_ID" "${APP_BUNDLE_ID:-}"

# --- ASC API Key (base64-encoded) ---
set_required_secret "ASC_KEY_ID" "${ASC_KEY_ID:-}"
set_required_secret "ASC_ISSUER_ID" "${ASC_ISSUER_ID:-}"

if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    ASC_KEY_PATH_EXPANDED=$(expand_path "${ASC_KEY_PATH}")
    ASC_KEY_BASENAME="$(basename "${ASC_KEY_PATH_EXPANDED}")"
    EXPECTED_KEY_BASENAME="AuthKey_${ASC_KEY_ID}.p8"
    if [[ "${ASC_KEY_BASENAME}" != "${EXPECTED_KEY_BASENAME}" ]]; then
        log_fail "ASC key filename mismatch. Expected ${EXPECTED_KEY_BASENAME}, got ${ASC_KEY_BASENAME}"
        exit 1
    fi
    if file_exists "${ASC_KEY_PATH_EXPANDED}"; then
        if ! grep -q "BEGIN PRIVATE KEY" "${ASC_KEY_PATH_EXPANDED}"; then
            log_fail "ASC key is not a valid .p8 PEM file: ${ASC_KEY_PATH_EXPANDED}"
            exit 1
        fi
        if ! openssl pkey -in "${ASC_KEY_PATH_EXPANDED}" -noout >/dev/null 2>&1; then
            log_fail "ASC key failed OpenSSL validation: ${ASC_KEY_PATH_EXPANDED}"
            exit 1
        fi
        if secret_exists "ASC_KEY_CONTENT" "$REPO" && ! $FORCE; then
            log_ok "ASC_KEY_CONTENT already exists — skipping"
        else
            ASC_KEY_CONTENT=$(base64 < "${ASC_KEY_PATH_EXPANDED}")
            gh secret set "ASC_KEY_CONTENT" --repo "$REPO" --body "$ASC_KEY_CONTENT"
            if $FORCE; then
                log_ok "ASC_KEY_CONTENT overwritten (base64 from ${ASC_KEY_PATH_EXPANDED})"
            else
                log_ok "ASC_KEY_CONTENT provisioned (base64 from ${ASC_KEY_PATH_EXPANDED})"
            fi
        fi
    else
        log_warn "ASC_KEY_PATH set but file not found: ${ASC_KEY_PATH} (expanded: ${ASC_KEY_PATH_EXPANDED})"
    fi
fi

# --- Match SSH key ---
if [[ -n "${MATCH_GIT_PRIVATE_KEY_PATH:-}" ]]; then
    MATCH_GIT_PRIVATE_KEY_PATH_EXPANDED=$(expand_path "${MATCH_GIT_PRIVATE_KEY_PATH}")
    if file_exists "${MATCH_GIT_PRIVATE_KEY_PATH_EXPANDED}"; then
        if secret_exists "MATCH_GIT_PRIVATE_KEY" "$REPO" && ! $FORCE; then
            log_ok "MATCH_GIT_PRIVATE_KEY already exists — skipping"
        else
            gh secret set "MATCH_GIT_PRIVATE_KEY" --repo "$REPO" < "${MATCH_GIT_PRIVATE_KEY_PATH_EXPANDED}"
            if $FORCE; then
                log_ok "MATCH_GIT_PRIVATE_KEY overwritten from ${MATCH_GIT_PRIVATE_KEY_PATH_EXPANDED}"
            else
                log_ok "MATCH_GIT_PRIVATE_KEY provisioned from ${MATCH_GIT_PRIVATE_KEY_PATH_EXPANDED}"
            fi
        fi
    else
        log_warn "MATCH_GIT_PRIVATE_KEY_PATH set but file not found: ${MATCH_GIT_PRIVATE_KEY_PATH} (expanded: ${MATCH_GIT_PRIVATE_KEY_PATH_EXPANDED})"
    fi
fi

log_ok "GitHub secrets provisioning complete"
