# Adding Watch / Widget / Extension Targets

This template generates a single iOS app target (iPhone + iPad). Watch apps, widgets, and other extensions are added manually in Xcode after bootstrap.

## Steps

### 1. Add the target in Xcode

Open your project and use **File > New > Target** to add:

- **watchOS App** — for Apple Watch
- **Widget Extension** — for WidgetKit
- **App Intent Extension**, **Notification Service Extension**, etc.

### 2. Register the new bundle ID

Each extension target gets its own bundle identifier (e.g., `com.company.myapp.watchkitapp`).

Register it in the Apple Developer Portal, or let Xcode do it automatically during development.

### 3. Update match for the new bundle ID

Add the new identifier to your Matchfile:

```ruby
app_identifier([
  "com.company.myapp",
  "com.company.myapp.watchkitapp",
  "com.company.myapp.widget"
])
```

Then regenerate certificates:

```bash
bundle exec fastlane match appstore --app_identifier "com.company.myapp.watchkitapp"
```

### 4. Update Fastfile export_options

If using manual signing with explicit provisioning profiles, add the new target's profile mapping:

```ruby
export_options: {
  signingStyle: "manual",
  provisioningProfiles: {
    "com.company.myapp" => "match AppStore com.company.myapp",
    "com.company.myapp.widget" => "match AppStore com.company.myapp.widget"
  }
}
```

### 5. Update GitHub Secrets if needed

If you added new bundle IDs that require separate provisioning, re-run:

```bash
./release/bootstrap/bootstrap.sh --init
```

Or manually update the `APP_BUNDLE_ID` secret to include all identifiers.

## Supported Platforms

| Platform | Included in Template | Add Manually |
|----------|---------------------|-------------|
| iPhone | Yes | — |
| iPad | Yes | — |
| Apple Watch | — | Xcode > New Target |
| Widget | — | Xcode > New Target |
| macOS (Catalyst) | — | Enable in Xcode project settings |
