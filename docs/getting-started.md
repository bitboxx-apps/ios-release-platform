# Getting Started

## Prerequisites

- macOS with Xcode 15+ installed
- Ruby >= 3.2
- Bundler (`gem install bundler`)
- GitHub CLI (`gh`)
- OpenSSL

Run the doctor to verify your environment:

```bash
./release/bootstrap/doctor.sh
```

## Quick Start

### 1. Create repository from template

Use this repository as a GitHub Template to create a new repository.

### 2. Configure environment

```bash
cp .env.platform.example .env.platform
cp .env.app.example .env.app
```

Edit `.env.platform` with your organization secrets:

- `APPLE_TEAM_ID` — your 10-character Apple Developer Team ID
- `MATCH_GIT_URL` — SSH URL to your signing certificate repository
- `MATCH_PASSWORD` — encryption password for the match repository

Edit `.env.app` with your app identity:

- `APP_NAME` — Xcode project name (no spaces, e.g., `MyApp`)
- `APP_DISPLAY_NAME` — name shown on the iOS home screen (spaces OK, e.g., `My App`)
- `APP_BUNDLE_ID` — your app's bundle identifier
- `ASC_KEY_ID` / `ASC_ISSUER_ID` — App Store Connect API credentials
- `ASC_KEY_PATH` — local path to your `.p8` API key file
- `MATCH_GIT_PRIVATE_KEY_PATH` — local path to SSH key for match repo

### 3. Run bootstrap

```bash
./release/bootstrap/bootstrap.sh --init
```

This will:

1. Validate your environment configuration
2. Generate the Xcode project with correct settings
3. Verify Ruby and fastlane
4. Generate fastlane configuration files
5. Set up match certificates
6. Provision GitHub Secrets (ASC key base64-encoded, SSH key for match)

### 4. Open and develop

```bash
open app/<APP_NAME>.xcodeproj
```

### 5. Subsequent runs

After initial setup, use normal mode:

```bash
./release/bootstrap/bootstrap.sh
```

## Windows Users

Windows supports secret provisioning and configuration only:

```powershell
.\release\bootstrap\bootstrap.ps1 -Init
```

iOS build operations require macOS.
