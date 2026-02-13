#!/usr/bin/env bash
# doctor.sh — Validate environment readiness
# Fails fast on any missing dependency. Never auto-installs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/release/scripts/ensure_idempotency.sh"

echo "============================================"
echo " iOS Release Platform — Environment Doctor"
echo "============================================"
echo ""

ERRORS=0

check_required() {
    local cmd="$1"
    local label="$2"
    local install_hint="$3"

    if command_exists "$cmd"; then
        local version
        # fastlane can hang while checking for updates in some environments.
        if [[ "$cmd" == "fastlane" ]]; then
            version=$(CI=1 FASTLANE_SKIP_UPDATE_CHECK=1 fastlane --version 2>/dev/null | head -1 || echo "installed")
        else
            version=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
        fi
        log_ok "${label}: ${version}"
    else
        log_fail "${label}: NOT FOUND"
        log_fail "  → ${install_hint}"
        ERRORS=$((ERRORS + 1))
    fi
}

check_ruby_version() {
    if ! command_exists "ruby"; then
        log_fail "Ruby: NOT FOUND"
        log_fail "  → Install Ruby >= 3.2 via rbenv or asdf"
        ERRORS=$((ERRORS + 1))
        return
    fi

    local ruby_ver
    ruby_ver=$(ruby -e 'print RUBY_VERSION')
    local major minor
    major=$(echo "$ruby_ver" | cut -d. -f1)
    minor=$(echo "$ruby_ver" | cut -d. -f2)

    if [[ "$major" -lt 3 ]] || { [[ "$major" -eq 3 ]] && [[ "$minor" -lt 2 ]]; }; then
        log_fail "Ruby: ${ruby_ver} (>= 3.2 required)"
        log_fail "  → Upgrade Ruby via rbenv or asdf"
        ERRORS=$((ERRORS + 1))
    else
        log_ok "Ruby: ${ruby_ver}"
    fi
}

# --- Core tools ---
log_step "Checking core dependencies"

check_required "git" "Git" "Install Git: https://git-scm.com/"
check_required "gh" "GitHub CLI" "Install gh: https://cli.github.com/"
check_required "openssl" "OpenSSL" "Install OpenSSL via your package manager"

# --- Ruby ---
log_step "Checking Ruby environment"
check_ruby_version
check_required "bundle" "Bundler" "gem install bundler"

# --- fastlane ---
log_step "Checking fastlane"
check_required "fastlane" "fastlane" "gem install fastlane or bundle install"

# --- macOS-specific ---
if is_macos; then
    log_step "Checking macOS-specific tools"

    if command_exists "xcode-select"; then
        XCODE_PATH=$(xcode-select -p 2>/dev/null || true)
        if [[ -n "$XCODE_PATH" ]] && [[ -d "$XCODE_PATH" ]]; then
            log_ok "Xcode CLI Tools: ${XCODE_PATH}"
        else
            log_fail "Xcode CLI Tools: NOT CONFIGURED"
            log_fail "  → Run: xcode-select --install"
            ERRORS=$((ERRORS + 1))
        fi
    else
        log_fail "xcode-select: NOT FOUND"
        log_fail "  → Install Xcode from the App Store"
        ERRORS=$((ERRORS + 1))
    fi

    if command_exists "xcodebuild"; then
        XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || echo "unknown")
        log_ok "Xcode: ${XCODE_VERSION}"
    else
        log_fail "xcodebuild: NOT FOUND"
        log_fail "  → Install Xcode from the App Store"
        ERRORS=$((ERRORS + 1))
    fi
else
    log_info "Skipping macOS-specific checks (running on $(uname -s))"
fi

# --- Summary ---
echo ""
echo "============================================"
if [[ "$ERRORS" -gt 0 ]]; then
    log_fail "Doctor found ${ERRORS} issue(s). Fix them before running bootstrap."
    exit 1
else
    log_ok "All checks passed. Environment is ready."
    exit 0
fi
