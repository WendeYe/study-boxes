# Study Boxes Distribution Checklist

Study Boxes is planned as a direct-download macOS app. Do not ship production secrets in the repository.

## Signing and Packaging

1. Use a Developer ID Application certificate for release builds.
2. Enable Hardened Runtime for release archives.
3. Archive with Xcode using the `StudyBoxes` scheme.
4. Export a signed `.app`.
5. Package as `.zip` or `.dmg`.
6. Notarize with `notarytool`.
7. Staple the notarization ticket.
8. Verify Gatekeeper acceptance on a clean Mac account.

## Sparkle 2

The codebase has an `UpdateManager` integration point that uses `SPUStandardUpdaterController` when Sparkle is linked.

To finish updates:

1. Add Swift Package dependency: `https://github.com/sparkle-project/Sparkle`
2. Link Sparkle to the `StudyBoxes` target.
3. Add the Sparkle framework copy/sign build phase if Xcode does not add it automatically.
4. Add production `SUFeedURL` to `Info.plist`.
5. Generate Sparkle signing keys outside this repository.
6. Sign release archives and publish the appcast.

Current placeholder appcast:

```text
https://example.com/study-boxes/appcast.xml
```

## Licensing

`LicenseManager` stores license metadata in Keychain/UserDefaults and activates Study Boxes Pro through Lemon Squeezy's License API. The app does not ship a Lemon Squeezy API secret; activation, validation, and deactivation use the customer's license key and Lemon Squeezy activation instance ID.

Lemon Squeezy product:

```text
Product ID: 1019393
Checkout URL: https://studyboxes.lemonsqueezy.com/checkout/buy/d0db9d0e-eab3-4322-9905-46e3e38469bc
```

Before production:

1. Confirm Lemon Squeezy live mode is approved and the checkout creates license keys.
2. Confirm the product activation limit is set to the intended public limit.
3. Test activation with a real Lemon Squeezy test purchase license key.
4. Confirm wrong-product, expired, disabled, and inactive licenses do not unlock Pro.
5. Keep offline grace behavior explicit.

## Crash Reporting

Study Boxes uses Sentry through Swift Package Manager, but crash reporting is off by default and starts only after the user enables it in Settings > Privacy and diagnostics.

Sentry project:

```text
Org: study-box
Project: study-macos
```

Before production:

1. Confirm the production DSN in the `SENTRY_DSN` Info.plist build setting.
2. Use environments `debug`, `beta`, and `production` for release channels.
3. Upload dSYMs for every distributed build with `scripts/upload-sentry-dsyms.sh`.
4. Store `SENTRY_AUTH_TOKEN` only in the local shell or CI secret store. Do not commit it.
5. Keep crash events free of study names, tasks, notes, URLs, file paths, app/window lists, license keys, email, tokens, and calendar feed links.

Local dSYM upload:

```sh
cp scripts/sentry.env.example /tmp/study-boxes-sentry.env
# Edit /tmp/study-boxes-sentry.env with a fresh token, then:
source /tmp/study-boxes-sentry.env
scripts/upload-sentry-dsyms.sh
```

If an auth token was pasted into chat, revoke it in Sentry and generate a new token before uploading release dSYMs.

## Non-Sandboxed App Notes

Study Boxes needs local workspace orchestration features that conflict with typical App Sandbox distribution. The direct-download build should document why Accessibility permission is requested and should continue working without it for non-window-management features.
