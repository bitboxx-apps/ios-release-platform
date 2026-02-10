# iOS Release Platform — Implementation Requirements

## Objective

Build a deterministic, enterprise-grade iOS release platform that is distributed as a GitHub Template.

The platform must allow a developer to:

1. Create a repository from the template.
2. Open the Xcode project immediately.
3. Configure `.env` files.
4. Execute a single bootstrap command.
5. Obtain a fully operational CI-ready release pipeline.

The system must behave as infrastructure — not as a developer convenience tool.

---

# CRITICAL REQUIREMENT

This repository is BOTH:

- an iOS App Template
- a Release Infrastructure Platform

The generated repository MUST be immediately usable for app development.

Failure to generate a working Xcode project is considered a critical failure.

---

# Core Principles

## Non-Interactive Execution
No script may require human input.

If required values are missing, the script must fail with a clear error.

Prompt-based workflows are forbidden.

---

## Idempotency
Running bootstrap multiple times must never:

- corrupt configuration
- duplicate secrets
- regenerate certificates unnecessarily
- overwrite user-modified files

All scripts must check for existing state before mutating it.

---

## Deterministic Behavior
Given identical inputs (.env), the platform must always produce identical results.

No hidden state is allowed.

---

## CI-First Design
The platform must assume execution inside CI.

Local execution is secondary.

---

# Repository Architecture (MANDATORY)

The repository MUST contain the following structure:

```
app/                    ← MUST contain a working Xcode project
release/
  bootstrap/
  scripts/
  platform/
    fastlane/
    templates/
    signing/
  policies/
  config/
docs/
.github/workflows/
```

---

## App Directory Requirements (CRITICAL)

The `app/` directory MUST:

- contain a valid `.xcodeproj`
- compile successfully
- use automatic signing initially
- have a placeholder bundle identifier
- build without fastlane

The app MUST be openable via:

```
open app/*.xcodeproj
```

Failure to meet this requirement is a platform failure.

---

## Separation of Concerns

fastlane, signing, CI, and bootstrap logic MUST NEVER exist inside the app directory.

The app must remain clean and focused on product code.

Release infrastructure must live exclusively under `/release`.

---

# Supported Environments

## macOS
Required for:

- fastlane
- signing
- certificate operations
- Xcode builds

## Windows
Supported only for:

- GitHub secret provisioning
- repository setup
- configuration generation

Windows must never attempt iOS build operations.

---

# Bootstrap System

## doctor.sh

Validate environment readiness.

Must verify:

- Ruby >= 3.2
- bundler
- fastlane
- git
- gh CLI
- OpenSSL
- Xcode CLI (macOS only)

Fail fast on any missing dependency.

Never auto-install system packages.

Only instruct the user.

---

## bootstrap.sh / bootstrap.ps1

Primary platform initializer.

Bootstrap MUST support two modes.

---

### INIT MODE (First Run Only)

```
bootstrap.sh --init
```

Responsibilities:

1. Validate `.env` against schema.
2. Ensure Ruby environment exists.
3. Ensure fastlane is installed.
4. Create the signing repository if it does not exist.
5. Configure match.
6. Generate certificates.
7. Provision GitHub secrets.
8. Generate fastlane configuration if absent.
9. Verify signing access.
10. Output a success report.

---

### NORMAL MODE

```
bootstrap.sh
```

Must:

- validate env
- ensure secrets exist
- run match in readonly mode
- verify fastlane readiness

MUST NOT regenerate certificates.

---

# Scripts

Each script must:

- be idempotent
- produce machine-readable logs
- exit on error

---

## setup_ruby.sh
Verify Ruby version only.

Do NOT install Ruby automatically.

---

## setup_fastlane.sh
Install fastlane only if missing.

---

## setup_match.sh
Initialize match in readonly mode unless explicitly overridden.

Never regenerate certificates automatically.

---

## setup_secrets.sh
Provision GitHub secrets using `gh`.

Must check for existence before creation.

Secrets must never be echoed to stdout.

---

## ensure_idempotency.sh
Provide reusable helpers such as:

- command_exists
- file_exists
- secret_exists

---

# Fastlane Templates

Provide:

- Fastfile
- Appfile
- Matchfile

Files must be generated only if absent.

Never overwrite existing configurations.

fastlane MUST run non-interactively.

Set:

```
CI=1
FASTLANE_SKIP_CONFIRMATION=1
```

---

# Configuration Schema

Create:

```
release/config/env.schema.json
```

Define:

- required variables
- optional variables
- type validation
- allowed patterns

Bootstrap must fail if schema validation fails.

No warnings.

Hard failure only.

---

# Environment Model

Use layered configuration:

## .env.platform
Organization-level constants.

## .env.app
Application-specific values.

## .env.local
Ignored by git.

Used for developer overrides.

Precedence:

.env.local > .env.app > .env.platform

---

# Security Requirements

## Secrets

Secrets must:

- never be logged
- never be committed
- never be printed

Use environment variables only.

---

## Signing Repository

Treat signing storage as infrastructure.

Scripts must never:

- delete certificates
- rotate keys automatically
- call `match nuke`

Explicit human approval must be required for destructive operations.

---

# Logging

Scripts must output structured logs:

Example:

[BOOTSTRAP] Checking Ruby  
[OK] Ruby 3.3 detected  
[FAIL] fastlane missing

Avoid verbose noise.

Prefer signal over chatter.

---

# Failure Model

Fail immediately when encountering:

- missing env variables
- unsupported OS
- insufficient permissions
- schema violations

Do not attempt recovery.

Do not guess values.

---

# Success Criteria

The platform is considered operational when:

1. The repository can be created from the template.
2. The Xcode project opens immediately.
3. `doctor.sh` passes.
4. `bootstrap.sh --init` completes without prompts.
5. GitHub secrets exist.
6. fastlane match runs in readonly mode.
7. CI builds without manual signing.

---

# Anti-Goals

Do NOT implement:

- GUI tools
- interactive installers
- certificate auto-regeneration
- hidden configuration
- magic defaults

Explicit configuration is mandatory.

---

# Implementation Style

Prefer:

- small scripts
- composable functions
- explicit checks
- predictable behavior

Avoid:

- monolithic scripts
- implicit assumptions
- silent failures

---

# Final Requirement

This platform must reduce release risk — not developer effort.

Safety > Convenience  
Predictability > Cleverness  
Infrastructure > Scripts
