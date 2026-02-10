# CI/CD Pipeline

## Workflows

### CI (`ci.yml`)

Triggered on every push to `main` and on pull requests.

- Reads `APP_NAME` from committed `.env.app`
- Builds the project without signing (simulator)
- Runs tests
- SPM dependency caching enabled

### Deploy (`deploy.yml`)

Triggered when a version tag (`v*`) is pushed, or manually via `workflow_dispatch`.

- Reads `APP_NAME` from committed `.env.app`
- Sets up Ruby 3.3 with bundler caching
- Runs `fastlane beta`:
  - Authenticates with App Store Connect API (base64-encoded key)
  - Syncs certificates via match (readonly, SSH key)
  - Auto-increments build number (`GITHUB_RUN_NUMBER + 1000`)
  - Builds signed IPA with manual signing
  - Uploads to TestFlight

## Required GitHub Secrets

| Secret | Description | Set By |
|--------|-------------|--------|
| `MATCH_GIT_URL` | Signing repo URL | `bootstrap.sh --init` |
| `MATCH_PASSWORD` | Match encryption password | `bootstrap.sh --init` |
| `MATCH_GIT_PRIVATE_KEY` | SSH key for signing repo | `bootstrap.sh --init` |
| `APPLE_TEAM_ID` | Apple Developer Team ID | `bootstrap.sh --init` |
| `APP_BUNDLE_ID` | App bundle identifier | `bootstrap.sh --init` |
| `ASC_KEY_ID` | App Store Connect Key ID | `bootstrap.sh --init` |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID | `bootstrap.sh --init` |
| `ASC_KEY_CONTENT` | App Store Connect key (base64) | `bootstrap.sh --init` |

## Triggering a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Build Number Strategy

Build numbers use `GITHUB_RUN_NUMBER + 1000` to:
- Ensure monotonic increase across CI runs
- Avoid conflicts with manually-set build numbers
- Start above any existing App Store Connect build numbers
