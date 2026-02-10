# Release Policy

## Build Pipeline

1. All releases must go through the CI pipeline.
2. Manual builds are for local testing only and must never be distributed.
3. Every release build must be signed with match-managed certificates.

## Version Management

- `MARKETING_VERSION` is the user-facing version (e.g., 1.2.0).
- `CURRENT_PROJECT_VERSION` is the build number, incremented on every release.
- Version bumps must be committed before triggering a release.

## Environments

| Environment | Trigger | Distribution |
|-------------|---------|-------------|
| Development | Push to feature branch | None |
| Beta | Push to main / manual | TestFlight |
| Production | Git tag `v*` | App Store |

## Failure Handling

- Failed builds must not retry automatically.
- Build failures must produce actionable error messages.
- No silent failures are allowed in the pipeline.
