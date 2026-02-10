#!/usr/bin/env bash
# create_project.sh — Generate Xcode project from templates
# Replaces __PLACEHOLDER__ markers with values from .env files.
# Idempotent: skips if app/*.xcodeproj already exists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/ensure_idempotency.sh"

TEMPLATE_DIR="${REPO_ROOT}/release/platform/templates/app"
APP_DIR="${REPO_ROOT}/app"

# ---------- Load and validate environment ----------

load_env_layers "$REPO_ROOT"

require_var "APP_NAME"
require_var "APP_DISPLAY_NAME"
require_var "APP_BUNDLE_ID"
require_var "APPLE_TEAM_ID"

# ---------- Validate APP_NAME is a valid Swift identifier ----------

if [[ ! "$APP_NAME" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    log_fail "APP_NAME must start with a letter and contain only letters, digits, or underscores"
    log_fail "Got: '${APP_NAME}'"
    log_fail "Use APP_DISPLAY_NAME for the user-visible name (spaces and special characters allowed)"
    exit 1
fi

# ---------- Idempotency: skip if project exists ----------

if ls "${APP_DIR}"/*.xcodeproj 1>/dev/null 2>&1; then
    EXISTING=$(ls -d "${APP_DIR}"/*.xcodeproj 2>/dev/null | head -1)
    log_ok "Xcode project already exists: ${EXISTING} — skipping generation"
    exit 0
fi

log_step "Generating Xcode project: ${APP_NAME}"

# ---------- Verify templates exist ----------

REQUIRED_TEMPLATES=(
    "project.pbxproj.template"
    "xcscheme.template"
    "xcworkspacedata.template"
    "AppEntry.swift.template"
    "ContentView.swift.template"
)

for tmpl in "${REQUIRED_TEMPLATES[@]}"; do
    if [[ ! -f "${TEMPLATE_DIR}/${tmpl}" ]]; then
        log_fail "Missing template: ${TEMPLATE_DIR}/${tmpl}"
        exit 1
    fi
done

if [[ ! -d "${TEMPLATE_DIR}/Assets.xcassets" ]]; then
    log_fail "Missing template directory: ${TEMPLATE_DIR}/Assets.xcassets"
    exit 1
fi

# ---------- Placeholder replacement via sed ----------
# Uses | as delimiter to avoid conflicts with dots in bundle IDs.
# Detects macOS vs Linux for sed -i syntax.

apply_placeholders() {
    local file="$1"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' \
            -e "s|__APP_NAME__|${APP_NAME}|g" \
            -e "s|__APP_BUNDLE_ID__|${APP_BUNDLE_ID}|g" \
            -e "s|__APPLE_TEAM_ID__|${APPLE_TEAM_ID}|g" \
            -e "s|__APP_DISPLAY_NAME__|${APP_DISPLAY_NAME}|g" \
            "$file"
    else
        sed -i \
            -e "s|__APP_NAME__|${APP_NAME}|g" \
            -e "s|__APP_BUNDLE_ID__|${APP_BUNDLE_ID}|g" \
            -e "s|__APPLE_TEAM_ID__|${APPLE_TEAM_ID}|g" \
            -e "s|__APP_DISPLAY_NAME__|${APP_DISPLAY_NAME}|g" \
            "$file"
    fi
}

# ---------- Create directory structure ----------

XCODEPROJ_DIR="${APP_DIR}/${APP_NAME}.xcodeproj"
SOURCE_DIR="${APP_DIR}/${APP_NAME}"

mkdir -p "${XCODEPROJ_DIR}/project.xcworkspace"
mkdir -p "${XCODEPROJ_DIR}/xcshareddata/xcschemes"
mkdir -p "${SOURCE_DIR}/Assets.xcassets/AccentColor.colorset"
mkdir -p "${SOURCE_DIR}/Assets.xcassets/AppIcon.appiconset"

# ---------- Generate project.pbxproj ----------

cp "${TEMPLATE_DIR}/project.pbxproj.template" "${XCODEPROJ_DIR}/project.pbxproj"
apply_placeholders "${XCODEPROJ_DIR}/project.pbxproj"
log_ok "project.pbxproj generated"

# ---------- Generate xcworkspacedata ----------

cp "${TEMPLATE_DIR}/xcworkspacedata.template" "${XCODEPROJ_DIR}/project.xcworkspace/contents.xcworkspacedata"
log_ok "xcworkspacedata generated"

# ---------- Generate xcscheme ----------

cp "${TEMPLATE_DIR}/xcscheme.template" "${XCODEPROJ_DIR}/xcshareddata/xcschemes/${APP_NAME}.xcscheme"
apply_placeholders "${XCODEPROJ_DIR}/xcshareddata/xcschemes/${APP_NAME}.xcscheme"
log_ok "${APP_NAME}.xcscheme generated"

# ---------- Generate Swift source files ----------

cp "${TEMPLATE_DIR}/AppEntry.swift.template" "${SOURCE_DIR}/${APP_NAME}App.swift"
apply_placeholders "${SOURCE_DIR}/${APP_NAME}App.swift"
log_ok "${APP_NAME}App.swift generated"

cp "${TEMPLATE_DIR}/ContentView.swift.template" "${SOURCE_DIR}/ContentView.swift"
log_ok "ContentView.swift generated"

# ---------- Copy asset catalogs ----------

cp "${TEMPLATE_DIR}/Assets.xcassets/Contents.json" "${SOURCE_DIR}/Assets.xcassets/Contents.json"
cp "${TEMPLATE_DIR}/Assets.xcassets/AccentColor.colorset/Contents.json" "${SOURCE_DIR}/Assets.xcassets/AccentColor.colorset/Contents.json"
cp "${TEMPLATE_DIR}/Assets.xcassets/AppIcon.appiconset/Contents.json" "${SOURCE_DIR}/Assets.xcassets/AppIcon.appiconset/Contents.json"
log_ok "Asset catalogs copied"

# ---------- Done ----------

log_ok "Xcode project generated: ${XCODEPROJ_DIR}"
log_info "Open with: open ${XCODEPROJ_DIR}"
