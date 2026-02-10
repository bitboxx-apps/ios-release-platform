# bootstrap.ps1 — Windows bootstrap for GitHub secret provisioning and setup
# Windows supports ONLY: secret provisioning, repository setup, configuration generation
# Windows must NEVER attempt iOS build operations.

param(
    [switch]$Init,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path

# ---------- Logging ----------

function Log-Info { param([string]$Message) Write-Host "[INFO] $Message" }
function Log-Ok { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Log-Fail { param([string]$Message) Write-Host "[FAIL] $Message" -ForegroundColor Red }
function Log-Step { param([string]$Message) Write-Host "[BOOTSTRAP] $Message" -ForegroundColor Cyan }

# ---------- Help ----------

if ($Help) {
    Write-Host "Usage: bootstrap.ps1 [-Init]"
    Write-Host ""
    Write-Host "  -Init    Provision GitHub secrets and validate configuration"
    Write-Host "  (default) Validate environment and verify secrets"
    Write-Host ""
    Write-Host "NOTE: Windows does not support iOS build operations."
    exit 0
}

# ---------- Env Loading ----------

function Load-EnvFile {
    param([string]$Path)
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#") -and $line -match "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
                [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
            }
        }
    }
}

function Load-EnvLayers {
    Load-EnvFile "$RepoRoot\.env.platform"
    Load-EnvFile "$RepoRoot\.env.app"
    Load-EnvFile "$RepoRoot\.env.local"
}

function Require-Var {
    param([string]$Name)
    $val = [System.Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $val) {
        Log-Fail "Required environment variable $Name is not set"
        exit 1
    }
}

function Command-Exists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# ---------- Main ----------

Write-Host "============================================"
Write-Host " iOS Release Platform — Bootstrap (Windows)"
Write-Host " Mode: $(if ($Init) { 'INIT' } else { 'NORMAL' })"
Write-Host "============================================"
Write-Host ""

# Step 1: Load environment
Log-Step "Loading environment configuration"
Load-EnvLayers

# Step 2: Validate required variables
Log-Step "Validating environment"
Require-Var "APP_BUNDLE_ID"
Require-Var "APP_NAME"
Require-Var "APP_DISPLAY_NAME"

# Derive APP_SCHEME and XCODE_PROJECT_PATH from APP_NAME
$appName = [System.Environment]::GetEnvironmentVariable("APP_NAME", "Process")
if ($appName -and -not [System.Environment]::GetEnvironmentVariable("APP_SCHEME", "Process")) {
    [System.Environment]::SetEnvironmentVariable("APP_SCHEME", $appName, "Process")
}
if ($appName -and -not [System.Environment]::GetEnvironmentVariable("XCODE_PROJECT_PATH", "Process")) {
    [System.Environment]::SetEnvironmentVariable("XCODE_PROJECT_PATH", "app/$appName.xcodeproj", "Process")
}

if ($Init) {
    Require-Var "MATCH_GIT_URL"
    Require-Var "MATCH_PASSWORD"
    Require-Var "APPLE_TEAM_ID"
}

Log-Ok "Environment validation passed"

# Step 3: Check gh CLI
Log-Step "Checking GitHub CLI"
if (-not (Command-Exists "gh")) {
    Log-Fail "gh CLI not found. Install from https://cli.github.com/"
    exit 1
}
Log-Ok "GitHub CLI available"

if ($Init) {
    # Step 4: Provision secrets
    Log-Step "Provisioning GitHub secrets"

    $secrets = @{
        "MATCH_GIT_URL" = [System.Environment]::GetEnvironmentVariable("MATCH_GIT_URL", "Process")
        "MATCH_PASSWORD" = [System.Environment]::GetEnvironmentVariable("MATCH_PASSWORD", "Process")
        "APPLE_TEAM_ID" = [System.Environment]::GetEnvironmentVariable("APPLE_TEAM_ID", "Process")
        "APP_BUNDLE_ID" = [System.Environment]::GetEnvironmentVariable("APP_BUNDLE_ID", "Process")
    }

    $repo = gh repo view --json nameWithOwner -q '.nameWithOwner' 2>$null
    if (-not $repo) {
        Log-Fail "Cannot determine repository. Ensure gh is authenticated."
        exit 1
    }

    foreach ($kv in $secrets.GetEnumerator()) {
        if (-not $kv.Value) {
            Log-Info "Skipping $($kv.Key) — empty value"
            continue
        }
        $existing = gh secret list --repo $repo 2>$null | Select-String "^$($kv.Key)\s"
        if ($existing) {
            Log-Ok "$($kv.Key) already exists — skipping"
        } else {
            $kv.Value | gh secret set $kv.Key --repo $repo --body -
            Log-Ok "$($kv.Key) provisioned"
        }
    }

    # Optional: ASC secrets
    $ascKeyId = [System.Environment]::GetEnvironmentVariable("ASC_KEY_ID", "Process")
    $ascIssuerId = [System.Environment]::GetEnvironmentVariable("ASC_ISSUER_ID", "Process")

    if ($ascKeyId) {
        $existing = gh secret list --repo $repo 2>$null | Select-String "^ASC_KEY_ID\s"
        if (-not $existing) {
            $ascKeyId | gh secret set "ASC_KEY_ID" --repo $repo --body -
            Log-Ok "ASC_KEY_ID provisioned"
        }
    }
    if ($ascIssuerId) {
        $existing = gh secret list --repo $repo 2>$null | Select-String "^ASC_ISSUER_ID\s"
        if (-not $existing) {
            $ascIssuerId | gh secret set "ASC_ISSUER_ID" --repo $repo --body -
            Log-Ok "ASC_ISSUER_ID provisioned"
        }
    }
} else {
    # Normal mode: verify secrets exist
    Log-Step "Verifying GitHub secrets"
    $repo = gh repo view --json nameWithOwner -q '.nameWithOwner' 2>$null
    if ($repo) {
        @("MATCH_GIT_URL", "MATCH_PASSWORD", "APPLE_TEAM_ID") | ForEach-Object {
            $existing = gh secret list --repo $repo 2>$null | Select-String "^$_\s"
            if ($existing) { Log-Ok "$_ exists" }
            else { Log-Fail "$_ not found — run bootstrap.ps1 -Init" }
        }
    } else {
        Log-Info "Cannot verify secrets — gh not authenticated"
    }
}

Write-Host ""
Write-Host "============================================"
Log-Ok "Bootstrap (Windows) complete"
Write-Host ""
Write-Host "  NOTE: iOS build operations require macOS."
Write-Host "  Use this machine for secret provisioning and configuration only."
Write-Host "============================================"
