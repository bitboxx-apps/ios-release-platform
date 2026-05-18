#!/usr/bin/env bash
# auto_provision.sh — Interactive setup wizard for first-time bootstrap.
#
# Walks the user through the minimum inputs (ASC API key + Apple Team ID),
# auto-derives or auto-creates everything else (match signing repo, SSH
# deploy key, MATCH_PASSWORD, .env.local), and offers an auto-or-manual
# choice for Bundle ID.
#
# Idempotent: a re-run reads existing values from .env.local / .env.app
# and only prompts for what's missing. Safe to interrupt and resume.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ensure_idempotency.sh
source "${SCRIPT_DIR}/ensure_idempotency.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_LOCAL="${REPO_ROOT}/.env.local"
ENV_APP="${REPO_ROOT}/.env.app"

require_command "gh" "Install GitHub CLI: https://cli.github.com/"
require_command "openssl"
require_command "ssh-keygen"

# ---------- .env.local read/write helpers ----------

env_local_value() {
    local key="$1"
    if [[ ! -f "$ENV_LOCAL" ]]; then
        echo ""
        return 0
    fi
    # grep returns 1 when no match — under set -o pipefail this would
    # propagate out and silently abort the command-sub caller. Capture it
    # explicitly so a missing key just yields an empty string.
    local raw
    raw="$(grep "^${key}=" "$ENV_LOCAL" 2>/dev/null || true)"
    echo "$raw" | tail -1 | cut -d= -f2- || true
}

env_app_value() {
    local key="$1"
    if [[ ! -f "$ENV_APP" ]]; then
        echo ""
        return 0
    fi
    local raw
    raw="$(grep "^${key}=" "$ENV_APP" 2>/dev/null || true)"
    echo "$raw" | tail -1 | cut -d= -f2- || true
}

upsert_env_local() {
    local key="$1"
    local value="$2"
    touch "$ENV_LOCAL"
    chmod 600 "$ENV_LOCAL"
    if grep -q "^${key}=" "$ENV_LOCAL" 2>/dev/null; then
        if is_macos; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_LOCAL"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_LOCAL"
        fi
    else
        echo "${key}=${value}" >> "$ENV_LOCAL"
    fi
}

upsert_env_app() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$ENV_APP" 2>/dev/null; then
        if is_macos; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_APP"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_APP"
        fi
    else
        echo "${key}=${value}" >> "$ENV_APP"
    fi
}

# ---------- Interactive helpers ----------

# prompt_required <var-name> <prompt-text> [validator-regex] [validator-hint]
# Prints the entered value to stdout. Re-prompts on empty/invalid input.
prompt_required() {
    local var_name="$1"
    local prompt_text="$2"
    local pattern="${3:-}"
    local hint="${4:-}"
    local current
    current="$(env_local_value "$var_name")"
    if [[ -n "$current" ]]; then
        log_ok "${var_name} already set in .env.local — skipping" >&2
        echo "$current"
        return
    fi
    local response=""
    while true; do
        read -r -p "  ${prompt_text}: " response < /dev/tty
        if [[ -z "$response" ]]; then
            echo "  (value cannot be empty)" >&2
            continue
        fi
        if [[ -n "$pattern" && ! "$response" =~ $pattern ]]; then
            echo "  (invalid format${hint:+ — $hint})" >&2
            continue
        fi
        break
    done
    echo "$response"
}

choose() {
    local prompt_text="$1"
    shift
    local options=("$@")
    local default_idx=1
    echo "  ${prompt_text}" >&2
    local i=1
    for opt in "${options[@]}"; do
        if [[ "$i" -eq "$default_idx" ]]; then
            echo "    ${i}) ${opt}  [default]" >&2
        else
            echo "    ${i}) ${opt}" >&2
        fi
        i=$((i+1))
    done
    local response=""
    while true; do
        read -r -p "  > " response < /dev/tty
        response="${response:-$default_idx}"
        if [[ "$response" =~ ^[0-9]+$ ]] && (( response >= 1 && response <= ${#options[@]} )); then
            break
        fi
        echo "  (please enter 1-${#options[@]})" >&2
    done
    echo "$response"
}

# ---------- Resolution ----------

resolve_default_org() {
    # Prefer the GitHub repo owner, fall back to the local git remote.
    local owner
    owner=$(gh repo view --json owner -q '.owner.login' 2>/dev/null || true)
    if [[ -z "$owner" ]]; then
        owner=$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null \
            | sed -E 's|.*[:/]([^/]+)/[^/]+(\.git)?$|\1|' || true)
    fi
    echo "$owner"
}

generate_bundle_id() {
    local org="$1"
    local app_name_lower
    app_name_lower="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
    local org_lower
    org_lower="$(echo "$org" | tr '[:upper:]' '[:lower:]' | sed 's/-/./g')"
    echo "jp.${org_lower}.${app_name_lower}"
}

# ---------- Wizard ----------

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  iOS Release Platform — Provision Wizard"
echo "═══════════════════════════════════════════════════════"
echo ""

load_env_layers "$REPO_ROOT"

REPO_OWNER="$(resolve_default_org)"
if [[ -z "$REPO_OWNER" ]]; then
    log_fail "Cannot determine GitHub org. Run 'gh auth login' or set 'git remote add origin'."
    exit 1
fi

# ─── Preflight: list manual prerequisites on first run ───
# Detect a fresh install (.env.local has none of the core ASC values yet)
# and show the human-only checklist. If the user has already populated
# .env.local, we skip the preflight — the wizard becomes a silent
# re-validation in that case.

if [[ -z "$(env_local_value ASC_KEY_ID)" \
   && -z "$(env_local_value ASC_ISSUER_ID)" \
   && -z "$(env_local_value APPLE_TEAM_ID)" ]]; then
    cat <<'PREFLIGHT'
┌─────────────────────────────────────────────────────────┐
│  Before continuing, complete these manual steps         │
│  in the Apple Developer / App Store Connect portal:     │
└─────────────────────────────────────────────────────────┘

  [1] Generate an App Store Connect API Key
      ▸ https://appstoreconnect.apple.com/access/integrations/api
      ▸ "Team Keys" tab → "+" → Role: Admin → Generate
      ▸ Download AuthKey_XXXXXXXXXX.p8 (one-time download)
      ▸ Copy: Key ID (10 chars)  +  Issuer ID (UUID)

  [2] Note your Team ID
      ▸ https://appstoreconnect.apple.com/access/users
      ▸ "Membership" → Team ID (10 chars)

  [3] Register the Bundle ID on Developer Portal
      ▸ https://developer.apple.com/account/resources/identifiers/list
      ▸ "+" → App IDs → App → Bundle ID type: Explicit
      ▸ Use the same value you'll pick in this wizard

  [4] Create the App record in App Store Connect
      ▸ https://appstoreconnect.apple.com/apps
      ▸ "+" → New App → choose the Bundle ID from step [3]
      ▸ Required — otherwise upload_to_testflight will fail
         with "App with bundle identifier 'X' was not found"

  Reference: README.md → Quick Start

PREFLIGHT

    read -r -p "  Done with [1]-[4]? Continue? [y/N]: " ack < /dev/tty
    case "${ack:-n}" in
        y|Y|yes|YES)
            log_ok "Continuing"
            echo ""
            ;;
        *)
            log_info "Exiting. Run again when you have the API key + Team ID + Bundle ID registered."
            exit 0
            ;;
    esac
fi

# ─── Step 1: ASC API credentials ──────────────────────────

echo "[1/6] App Store Connect API credentials"
echo "      → appstoreconnect.apple.com → Users and Access → Integrations → Team Keys"
echo ""

ASC_KEY_ID_VAL="$(prompt_required ASC_KEY_ID 'ASC_KEY_ID (10-char alphanumeric)' '^[A-Z0-9]{10}$' '10 uppercase letters/digits')"
upsert_env_local ASC_KEY_ID "$ASC_KEY_ID_VAL"

ASC_ISSUER_ID_VAL="$(prompt_required ASC_ISSUER_ID 'ASC_ISSUER_ID (UUID format)' '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' 'lowercase UUID')"
upsert_env_local ASC_ISSUER_ID "$ASC_ISSUER_ID_VAL"

ASC_KEY_PATH_RAW="$(prompt_required ASC_KEY_PATH 'ASC_KEY_PATH (path to AuthKey_*.p8)')"
ASC_KEY_PATH_EXPANDED="${ASC_KEY_PATH_RAW/#\~/$HOME}"
if [[ ! -f "$ASC_KEY_PATH_EXPANDED" ]]; then
    log_fail "File not found: $ASC_KEY_PATH_EXPANDED"
    exit 1
fi
if ! grep -q "BEGIN PRIVATE KEY" "$ASC_KEY_PATH_EXPANDED"; then
    log_fail "Not a valid .p8 PEM file: $ASC_KEY_PATH_EXPANDED"
    exit 1
fi
upsert_env_local ASC_KEY_PATH "$ASC_KEY_PATH_RAW"

# ─── Step 2: Apple Team ID ────────────────────────────────

echo ""
echo "[2/6] Apple Developer Team ID"
echo "      → appstoreconnect.apple.com → Membership → Team ID"
echo ""

APPLE_TEAM_ID_VAL="$(prompt_required APPLE_TEAM_ID 'APPLE_TEAM_ID (10-char from Membership page)' '^[A-Z0-9]{10}$' '10 uppercase letters/digits')"
upsert_env_local APPLE_TEAM_ID "$APPLE_TEAM_ID_VAL"

# ─── Step 3: Bundle ID ────────────────────────────────────

echo ""
echo "[3/6] Bundle ID"
echo ""

CURRENT_BUNDLE_ID="$(env_app_value APP_BUNDLE_ID)"
APP_NAME_VAL="$(env_app_value APP_NAME)"
SUGGESTED_BUNDLE_ID="$(generate_bundle_id "$REPO_OWNER" "$APP_NAME_VAL")"

BUNDLE_ID_FINAL=""
if [[ -n "$CURRENT_BUNDLE_ID" ]]; then
    echo "  Current value: ${CURRENT_BUNDLE_ID}  (from .env.app)"
    choice="$(choose 'How to set the Bundle ID?' \
        "Keep current: ${CURRENT_BUNDLE_ID}" \
        "Auto-generate: ${SUGGESTED_BUNDLE_ID}" \
        "Enter manually")"
    case "$choice" in
        1) BUNDLE_ID_FINAL="$CURRENT_BUNDLE_ID" ;;
        2) BUNDLE_ID_FINAL="$SUGGESTED_BUNDLE_ID" ;;
        3) BUNDLE_ID_FINAL="$(prompt_required _BUNDLE_ID_INPUT 'Bundle ID (reverse-DNS, e.g. jp.example.myapp)' '^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9\-]*)+$' 'reverse-DNS')" ;;
    esac
else
    choice="$(choose 'No Bundle ID in .env.app — how to set it?' \
        "Auto-generate: ${SUGGESTED_BUNDLE_ID}" \
        "Enter manually")"
    case "$choice" in
        1) BUNDLE_ID_FINAL="$SUGGESTED_BUNDLE_ID" ;;
        2) BUNDLE_ID_FINAL="$(prompt_required _BUNDLE_ID_INPUT 'Bundle ID (reverse-DNS, e.g. jp.example.myapp)' '^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9\-]*)+$' 'reverse-DNS')" ;;
    esac
fi

if [[ "$BUNDLE_ID_FINAL" != "$CURRENT_BUNDLE_ID" ]]; then
    upsert_env_app APP_BUNDLE_ID "$BUNDLE_ID_FINAL"
    log_ok "Updated .env.app: APP_BUNDLE_ID=${BUNDLE_ID_FINAL}"
fi
export APP_BUNDLE_ID="$BUNDLE_ID_FINAL"

# ─── Step 4: Match signing repository ─────────────────────

echo ""
echo "[4/6] Match signing repository"
echo ""

CURRENT_MATCH_GIT_URL="$(env_local_value MATCH_GIT_URL)"
MATCH_GIT_URL_FINAL=""
SIGNING_REPO_FULL=""   # owner/name — empty if user passed a custom URL

if [[ -n "$CURRENT_MATCH_GIT_URL" ]]; then
    log_ok "MATCH_GIT_URL already set: ${CURRENT_MATCH_GIT_URL} — skipping"
    MATCH_GIT_URL_FINAL="$CURRENT_MATCH_GIT_URL"
    SIGNING_REPO_FULL="$(echo "$CURRENT_MATCH_GIT_URL" | sed -E 's|^git@github\.com:([^/]+)/([^/]+)\.git$|\1/\2|')"
else
    DEFAULT_SIGNING_REPO_NAME="$(echo "$APP_NAME_VAL" | tr '[:upper:]' '[:lower:]')-signing"
    DEFAULT_SIGNING_REPO_FULL="${REPO_OWNER}/${DEFAULT_SIGNING_REPO_NAME}"
    choice="$(choose 'Match needs a private repo to store encrypted certs/profiles.' \
        "Auto-create private repo: ${DEFAULT_SIGNING_REPO_FULL}" \
        "Use an existing repo (enter URL)" \
        "Auto-create private repo with a custom name (under ${REPO_OWNER})")"

    # Track whether the signing repo was created fresh by this wizard run
    # (true) or already existed (false). When false, the repo may contain
    # encrypted certs from a previous match init — in that case Step 6
    # MUST ask for the existing MATCH_PASSWORD rather than generating a
    # new one, otherwise `match` cannot decrypt the repo.
    SIGNING_REPO_NEWLY_CREATED=false

    create_repo_if_missing() {
        local full="$1"
        if gh repo view "$full" >/dev/null 2>&1; then
            log_ok "Repo ${full} already exists — reusing"
            SIGNING_REPO_NEWLY_CREATED=false
        else
            log_step "Creating ${full}"
            gh repo create "$full" --private --description "Encrypted iOS signing certs for ${APP_NAME_VAL} (managed by fastlane match)" >/dev/null
            log_ok "Created ${full}"
            SIGNING_REPO_NEWLY_CREATED=true
        fi
    }

    case "$choice" in
        1)
            create_repo_if_missing "$DEFAULT_SIGNING_REPO_FULL"
            MATCH_GIT_URL_FINAL="git@github.com:${DEFAULT_SIGNING_REPO_FULL}.git"
            SIGNING_REPO_FULL="$DEFAULT_SIGNING_REPO_FULL"
            ;;
        2)
            MATCH_GIT_URL_FINAL="$(prompt_required _MATCH_GIT_URL 'MATCH_GIT_URL (e.g. git@github.com:org/repo.git)' '^git@github\.com:[^/]+/[^/]+\.git$' 'git@github.com:org/repo.git')"
            SIGNING_REPO_FULL="$(echo "$MATCH_GIT_URL_FINAL" | sed -E 's|^git@github\.com:([^/]+)/([^/]+)\.git$|\1/\2|')"
            ;;
        3)
            CUSTOM_REPO_NAME="$(prompt_required _CUSTOM_SIGNING_REPO_NAME "Repository name only (will be created as ${REPO_OWNER}/<name>)" '^[A-Za-z0-9._-]+$' 'GitHub-allowed chars: letters/digits/._-')"
            CUSTOM_SIGNING_REPO_FULL="${REPO_OWNER}/${CUSTOM_REPO_NAME}"
            create_repo_if_missing "$CUSTOM_SIGNING_REPO_FULL"
            MATCH_GIT_URL_FINAL="git@github.com:${CUSTOM_SIGNING_REPO_FULL}.git"
            SIGNING_REPO_FULL="$CUSTOM_SIGNING_REPO_FULL"
            ;;
    esac
    upsert_env_local MATCH_GIT_URL "$MATCH_GIT_URL_FINAL"
fi

# ─── Step 5: SSH deploy key for signing repo ──────────────

echo ""
echo "[5/6] SSH deploy key for signing repo"
echo ""

CURRENT_SSH_PATH="$(env_local_value MATCH_GIT_PRIVATE_KEY_PATH)"
SSH_KEY_PATH_FINAL=""

APP_NAME_LOWER="$(echo "$APP_NAME_VAL" | tr '[:upper:]' '[:lower:]')"

# Phase A — resolve the local key file path
if [[ -n "$CURRENT_SSH_PATH" ]] && [[ -f "${CURRENT_SSH_PATH/#\~/$HOME}" ]]; then
    log_ok "SSH key already exists at ${CURRENT_SSH_PATH} — reusing"
    SSH_KEY_PATH_FINAL="$CURRENT_SSH_PATH"
else
    SSH_KEY_PATH_FINAL="$HOME/.ssh/match_${APP_NAME_LOWER}_ed25519"
    if [[ -f "$SSH_KEY_PATH_FINAL" ]]; then
        log_ok "SSH key already on disk at ${SSH_KEY_PATH_FINAL} — reusing"
    else
        log_step "Generating Ed25519 SSH key at ${SSH_KEY_PATH_FINAL}"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH_FINAL" -N "" -C "match-deploy-${APP_NAME_LOWER}" >/dev/null
        log_ok "SSH key generated"
    fi
    upsert_env_local MATCH_GIT_PRIVATE_KEY_PATH "$SSH_KEY_PATH_FINAL"
fi

# Phase B — always ensure the deploy key is registered on the signing
# repo. Skipping this when only the LOCAL file exists would leave a
# stale .env.local pointing at a key that the signing repo has never
# seen (which happens if the user deletes & recreates the signing repo).
SSH_KEY_LOCAL_PATH="${SSH_KEY_PATH_FINAL/#\~/$HOME}"
if [[ -n "$SIGNING_REPO_FULL" ]] && [[ -f "${SSH_KEY_LOCAL_PATH}.pub" ]]; then
    DEPLOY_KEY_TITLE="match-ci-${APP_NAME_LOWER}"
    PUB_KEY_CONTENT="$(cat "${SSH_KEY_LOCAL_PATH}.pub")"
    EXISTING_TITLE="$(gh api "repos/${SIGNING_REPO_FULL}/keys" --jq ".[] | select(.title == \"${DEPLOY_KEY_TITLE}\") | .title" 2>/dev/null || true)"
    if [[ -n "$EXISTING_TITLE" ]]; then
        log_ok "Deploy key '${DEPLOY_KEY_TITLE}' already registered on ${SIGNING_REPO_FULL}"
    else
        log_step "Adding deploy key (write access) to ${SIGNING_REPO_FULL}"
        gh api "repos/${SIGNING_REPO_FULL}/keys" \
            --method POST \
            -f title="${DEPLOY_KEY_TITLE}" \
            -f key="$PUB_KEY_CONTENT" \
            -F read_only=false >/dev/null
        log_ok "Deploy key registered as '${DEPLOY_KEY_TITLE}'"
    fi
elif [[ -z "$SIGNING_REPO_FULL" ]]; then
    log_warn "Custom MATCH_GIT_URL — register $(basename "${SSH_KEY_PATH_FINAL}").pub as a Deploy key on that repo manually."
fi

# ─── Step 6: Match encryption password ────────────────────

echo ""
echo "[6/6] Match encryption password"
echo ""

CURRENT_MATCH_PASSWORD="$(env_local_value MATCH_PASSWORD)"

# Decide whether the signing repo can be safely treated as empty.
# If gh can see the repo, we check its size — a non-empty repo almost
# always means there are pre-existing encrypted match certs, so we MUST
# reuse the original MATCH_PASSWORD instead of generating a new one.
SIGNING_REPO_HAS_CONTENT=false
if [[ -n "$SIGNING_REPO_FULL" ]]; then
    REPO_SIZE="$(gh api "repos/${SIGNING_REPO_FULL}" --jq .size 2>/dev/null || echo 0)"
    if [[ "$REPO_SIZE" =~ ^[0-9]+$ ]] && (( REPO_SIZE > 0 )); then
        SIGNING_REPO_HAS_CONTENT=true
    fi
fi

if [[ -n "$CURRENT_MATCH_PASSWORD" ]]; then
    log_ok "MATCH_PASSWORD already set — skipping"
elif [[ "$SIGNING_REPO_HAS_CONTENT" == "true" ]]; then
    log_warn "Signing repo ${SIGNING_REPO_FULL} already contains data —"
    log_warn "almost certainly encrypted certs from a previous match run."
    log_warn "Enter the ORIGINAL MATCH_PASSWORD that was used to encrypt"
    log_warn "those certs. If you don't have it, you'll need to either"
    log_warn "recover it or wipe the repo (gh repo delete + re-run wizard)."
    echo ""
    MATCH_PASSWORD_VAL="$(prompt_required _EXISTING_MATCH_PASSWORD 'Existing MATCH_PASSWORD (the passphrase that encrypted the certs in the signing repo)')"
    upsert_env_local MATCH_PASSWORD "$MATCH_PASSWORD_VAL"
    log_ok "Saved existing MATCH_PASSWORD to .env.local"
else
    # 40 alphanum chars, no symbols (avoids shell-quoting headaches in CI).
    MATCH_PASSWORD_VAL="$(openssl rand -base64 60 | tr -dc 'A-Za-z0-9' | head -c 40)"
    upsert_env_local MATCH_PASSWORD "$MATCH_PASSWORD_VAL"
    log_ok "Generated random 40-char MATCH_PASSWORD and saved to .env.local"
fi

# ─── Done ─────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
log_ok "Wizard complete. .env.local contains:"
echo ""
grep -E "^(ASC_KEY_ID|ASC_ISSUER_ID|ASC_KEY_PATH|APPLE_TEAM_ID|MATCH_GIT_URL|MATCH_GIT_PRIVATE_KEY_PATH|MATCH_PASSWORD)=" "$ENV_LOCAL" \
    | sed -E 's|^(MATCH_PASSWORD)=.*|\1=<hidden>|; s|^(ASC_ISSUER_ID)=([0-9a-f]{8})[-0-9a-f]+|\1=\2-...|' \
    | sed 's|^|    |'
echo ""
echo "═══════════════════════════════════════════════════════"
