#!/usr/bin/env bash
# setup_fastlane.sh — Install fastlane only if missing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ensure_idempotency.sh"

log_step "Checking fastlane installation"

if command_exists "fastlane"; then
    FASTLANE_VERSION=$(fastlane --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    log_ok "fastlane ${FASTLANE_VERSION} already installed"
    exit 0
fi

log_info "fastlane not found — installing via bundler"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GEMFILE_PATH="${REPO_ROOT}/release/platform/Gemfile"

if file_exists "$GEMFILE_PATH"; then
    log_info "Installing from Gemfile: ${GEMFILE_PATH}"
    BUNDLE_GEMFILE="$GEMFILE_PATH" bundle install
else
    log_info "No Gemfile found — installing fastlane gem directly"
    gem install fastlane --no-document
fi

if command_exists "fastlane"; then
    FASTLANE_VERSION=$(fastlane --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    log_ok "fastlane ${FASTLANE_VERSION} installed successfully"
else
    log_fail "fastlane installation failed"
    exit 1
fi
