# Signing Policy

## Certificate Management

- Certificates are managed exclusively through fastlane match.
- Manual certificate creation is prohibited.
- Certificate rotation requires explicit human approval.

## Prohibited Operations

The following operations are **never** performed automatically:

- `match nuke` — destroying all certificates
- Certificate deletion from the signing repository
- Automatic key rotation
- Overwriting existing valid certificates

## Match Modes

| Mode | When Used | Auto-Triggered |
|------|-----------|---------------|
| `readonly` | Normal bootstrap, CI builds | Yes |
| `generate` | Init mode only (`--init`) | Yes (first run) |
| `nuke` | Never | No — requires manual execution |

## Signing Repository

The signing repository is infrastructure. Treat it as such:

- Access is restricted to CI and authorized developers.
- The repository must be private.
- The MATCH_PASSWORD must be stored as a GitHub secret.
- Direct pushes to the signing repo are prohibited.
