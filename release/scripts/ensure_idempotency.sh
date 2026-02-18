#!/usr/bin/env bash
# ensure_idempotency.sh — Reusable idempotency helpers
# Source this file in other scripts: source "$(dirname "$0")/ensure_idempotency.sh"

set -euo pipefail

# ---------- Logging ----------

log_info() {
    echo "[INFO] $*"
}

log_ok() {
    echo "[OK] $*"
}

log_fail() {
    echo "[FAIL] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_step() {
    echo "[BOOTSTRAP] $*"
}

# ---------- Existence Checks ----------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

file_exists() {
    [[ -f "$1" ]]
}

dir_exists() {
    [[ -d "$1" ]]
}

secret_exists() {
    local secret_name="$1"
    local repo="${2:-}"
    if [[ -z "$repo" ]]; then
        gh secret list 2>/dev/null | grep -q "^${secret_name}[[:space:]]"
    else
        gh secret list --repo "$repo" 2>/dev/null | grep -q "^${secret_name}[[:space:]]"
    fi
}

# ---------- Environment ----------

require_var() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        log_fail "Required environment variable ${var_name} is not set"
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    if ! command_exists "$cmd"; then
        log_fail "${cmd} is not installed"
        if [[ -n "$install_hint" ]]; then
            log_fail "Install it with: ${install_hint}"
        fi
        exit 1
    fi
}

# ---------- Env File Loading ----------

load_env_file() {
    local env_file="$1"
    if file_exists "$env_file"; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Normalize CRLF input from editors/CI copies.
            line="${line%$'\r'}"
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// /}" ]] && continue
            # Only export if it looks like KEY=VALUE
            if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                export "${line?}"
            fi
        done < "$env_file"
    fi
}

load_env_layers() {
    local root_dir="$1"
    # Load in precedence order (last wins)
    load_env_file "${root_dir}/.env.platform"
    load_env_file "${root_dir}/.env.app"
    load_env_file "${root_dir}/.env.local"
}

# ---------- Validation ----------

validate_env_schema() {
    local root_dir="$1"
    local schema_file="${root_dir}/release/config/env.schema.json"

    if ! file_exists "$schema_file"; then
        log_fail "Schema file not found: ${schema_file}"
        exit 1
    fi

    # Read required fields from schema and validate
    local required_vars
    required_vars=$(python3 -c "
import json, sys
with open('${schema_file}') as f:
    schema = json.load(f)
for var in schema.get('required', []):
    print(var)
" 2>/dev/null || true)

    if [[ -z "$required_vars" ]]; then
        log_warn "Could not parse schema; skipping validation"
        return 0
    fi

    local missing=0
    while IFS= read -r var; do
        if [[ -z "${!var:-}" ]]; then
            log_fail "Required variable missing: ${var}"
            missing=1
        fi
    done <<< "$required_vars"

    if [[ "$missing" -eq 1 ]]; then
        log_fail "Environment validation failed — check .env files"
        exit 1
    fi

    log_ok "Environment schema validation passed"
}

# ---------- Derived Variables ----------

derive_app_vars() {
    if [[ -n "${APP_NAME:-}" ]]; then
        export APP_SCHEME="${APP_SCHEME:-${APP_NAME}}"
        export XCODE_PROJECT_PATH="${XCODE_PROJECT_PATH:-app/${APP_NAME}.xcodeproj}"
    fi
}

# ---------- OS Detection ----------

is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

require_macos() {
    if ! is_macos; then
        log_fail "This operation requires macOS"
        exit 1
    fi
}
