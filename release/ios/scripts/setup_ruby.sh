#!/usr/bin/env bash
# setup_ruby.sh — Verify Ruby version meets requirements
# Does NOT install Ruby automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ensure_idempotency.sh"

REQUIRED_RUBY_MAJOR=3
REQUIRED_RUBY_MINOR=2

log_step "Checking Ruby installation"

require_command "ruby" "Install Ruby >= ${REQUIRED_RUBY_MAJOR}.${REQUIRED_RUBY_MINOR} via rbenv, asdf, or your system package manager"

RUBY_VERSION_FULL=$(ruby -e 'print RUBY_VERSION')
RUBY_MAJOR=$(echo "$RUBY_VERSION_FULL" | cut -d. -f1)
RUBY_MINOR=$(echo "$RUBY_VERSION_FULL" | cut -d. -f2)

if [[ "$RUBY_MAJOR" -lt "$REQUIRED_RUBY_MAJOR" ]] || \
   { [[ "$RUBY_MAJOR" -eq "$REQUIRED_RUBY_MAJOR" ]] && [[ "$RUBY_MINOR" -lt "$REQUIRED_RUBY_MINOR" ]]; }; then
    log_fail "Ruby ${RUBY_VERSION_FULL} found, but >= ${REQUIRED_RUBY_MAJOR}.${REQUIRED_RUBY_MINOR} is required"
    log_fail "Install a newer Ruby via rbenv, asdf, or your system package manager"
    exit 1
fi

log_ok "Ruby ${RUBY_VERSION_FULL} detected"

# Verify bundler
log_step "Checking bundler"
require_command "bundle" "gem install bundler"
BUNDLER_VERSION=$(bundle version | awk '{print $3}')
log_ok "Bundler ${BUNDLER_VERSION} detected"
