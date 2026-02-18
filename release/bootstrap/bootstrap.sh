#!/usr/bin/env bash
# bootstrap.sh — Primary platform initializer
# Supports two modes: --init (first run) and normal (subsequent runs)
# Non-interactive. Fails on error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/release/scripts"

source "${SCRIPTS_DIR}/ensure_idempotency.sh"

# fastlane can hang while checking for updates; make bootstrap non-interactive.
export CI=1
export FASTLANE_SKIP_UPDATE_CHECK=1

# ---------- Parse Arguments ----------

INIT_MODE=false
FORCE_SECRETS=false
for arg in "$@"; do
    case "$arg" in
        --init) INIT_MODE=true ;;
        --force-secrets) FORCE_SECRETS=true ;;
        --help|-h)
            echo "Usage: bootstrap.sh [--init] [--force-secrets]"
            echo ""
            echo "  --init    First-time initialization (generates Xcode project, creates certs, provisions secrets)"
            echo "  --force-secrets  Overwrite existing GitHub secrets when provisioning"
            echo "  (default) Normal mode: validates env, syncs match readonly, verifies readiness"
            exit 0
            ;;
        *)
            log_fail "Unknown argument: ${arg}"
            exit 1
            ;;
    esac
done

echo "============================================"
echo " iOS Release Platform — Bootstrap"
echo " Mode: $(if $INIT_MODE; then echo 'INIT'; else echo 'NORMAL'; fi)"
echo "============================================"
echo ""

# ---------- Step 1: Load and validate environment ----------

log_step "Loading environment configuration"
load_env_layers "$REPO_ROOT"
derive_app_vars

log_step "Validating environment against schema"
validate_env_schema "$REPO_ROOT"

# ---------- Step 2: Generate Xcode project if needed ----------

log_step "Ensuring Xcode project exists"
bash "${SCRIPTS_DIR}/create_project.sh"

# ---------- Step 3: Verify Ruby ----------

log_step "Verifying Ruby environment"
bash "${SCRIPTS_DIR}/setup_ruby.sh"

# ---------- Step 4: Install fastlane if needed ----------

log_step "Ensuring fastlane is available"
bash "${SCRIPTS_DIR}/setup_fastlane.sh"

# ---------- Step 5: Generate fastlane configuration if absent ----------

log_step "Ensuring fastlane configuration exists"

FASTLANE_DIR="${REPO_ROOT}/release/platform/fastlane"
FL_TEMPLATE_DIR="${REPO_ROOT}/release/platform/templates"

generate_from_template() {
    local target="$1"
    local template="$2"
    local name
    name=$(basename "$target")

    if file_exists "$target"; then
        log_ok "${name} already exists — skipping"
        return
    fi

    if file_exists "$template"; then
        mkdir -p "$(dirname "$target")"
        envsubst < "$template" > "$target"
        log_ok "${name} generated from template"
    else
        log_warn "Template not found: ${template} — skipping ${name}"
    fi
}

generate_from_template "${FASTLANE_DIR}/Fastfile" "${FL_TEMPLATE_DIR}/Fastfile.template"
generate_from_template "${FASTLANE_DIR}/Appfile" "${FL_TEMPLATE_DIR}/Appfile.template"

# ---------- INIT MODE ONLY ----------

if $INIT_MODE; then
    require_macos

    # Step 6: Create signing repository if it doesn't exist
    log_step "Checking signing repository"
    if gh repo view "${MATCH_GIT_URL%.git}" >/dev/null 2>&1; then
        log_ok "Signing repository already exists"
    else
        log_info "Signing repository not found — it must be created manually"
        log_fail "Create the match signing repository first: ${MATCH_GIT_URL}"
        log_fail "Then re-run bootstrap.sh --init"
        exit 1
    fi

    # Step 7: Configure match and generate certificates
    log_step "Configuring match and generating certificates"
    bash "${SCRIPTS_DIR}/setup_match.sh" "false" "true"

    # Step 8: Provision GitHub secrets
    log_step "Provisioning GitHub secrets"
    if $FORCE_SECRETS; then
        bash "${SCRIPTS_DIR}/setup_secrets.sh" --force
    else
        bash "${SCRIPTS_DIR}/setup_secrets.sh"
    fi

    # Step 9: Verify signing access
    log_step "Verifying signing access (readonly match)"
    bash "${SCRIPTS_DIR}/setup_match.sh" "true" "false"

else
    # ---------- NORMAL MODE ----------

    # Step 6: Ensure secrets exist
    log_step "Verifying GitHub secrets"
    REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
    if [[ -n "$REPO" ]]; then
        REQUIRED_SECRETS=("MATCH_GIT_URL" "MATCH_PASSWORD" "APPLE_TEAM_ID")
        for secret_name in "${REQUIRED_SECRETS[@]}"; do
            if secret_exists "$secret_name" "$REPO"; then
                log_ok "Secret ${secret_name} exists"
            else
                log_warn "Secret ${secret_name} not found — run bootstrap.sh --init to provision"
            fi
        done
    else
        log_warn "Cannot verify secrets — gh not authenticated or not in a repo"
    fi

    # Step 7: Run match in readonly mode
    if is_macos; then
        log_step "Running match in readonly mode"
        bash "${SCRIPTS_DIR}/setup_match.sh" "true" "false"
    else
        log_info "Skipping match sync (not on macOS)"
    fi
fi

# ---------- Success Report ----------

echo ""
echo "============================================"
log_ok "Bootstrap complete"
echo ""
echo "  App project:  ${REPO_ROOT}/app/${APP_NAME}.xcodeproj"
echo "  Fastlane dir: ${FASTLANE_DIR}"
echo "  Mode:         $(if $INIT_MODE; then echo 'INIT'; else echo 'NORMAL'; fi)"
echo ""
echo "  Open your project:"
echo "    open app/${APP_NAME}.xcodeproj"
echo "============================================"
