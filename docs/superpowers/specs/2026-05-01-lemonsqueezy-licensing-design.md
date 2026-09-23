# Lemon Squeezy Licensing Design

## Goal

Replace the local `SB-` placeholder licensing path with Lemon Squeezy's License API so paid customers can activate Study Boxes Pro directly from the app.

## Approved Approach

Use Lemon Squeezy's public License API directly from the macOS app. The app sends only the license key entered by the customer and the activation instance ID returned by Lemon Squeezy. No Lemon Squeezy API secret is shipped in the app.

## Product Configuration

- Product ID: `1019393`
- Checkout URL: `https://studyboxes.lemonsqueezy.com/checkout/buy/d0db9d0e-eab3-4322-9905-46e3e38469bc`
- Variant ID: not required for v1 because the product has no user-facing variant.

Study Boxes unlocks Pro only when Lemon Squeezy confirms a valid, non-expired, non-disabled license for product `1019393`.

## Components

- `LicenseManager` remains the UI-facing source of truth for license state, entitlement plan, offline grace, activation, validation, and deactivation.
- A new Lemon Squeezy API client implements `LicenseAPIClientProtocol`.
- `LicenseConfiguration` centralizes the production product ID and checkout URL.
- `LicenseView` exposes a `Buy Pro` button and removes placeholder purchase copy.

## Data Flow

Activation:
1. User buys Pro from the Lemon Squeezy checkout.
2. User pastes the license key in Settings > License.
3. Study Boxes calls `POST /v1/licenses/activate` with `license_key` and an instance name.
4. The response must be activated and must match product ID `1019393`.
5. The license key, instance ID, and local metadata are stored with the existing Keychain/UserDefaults split.

Validation:
1. Study Boxes loads stored `license_key`, `instance_id`, and token-compatible instance value from Keychain.
2. Study Boxes calls `POST /v1/licenses/validate`.
3. A valid matching product keeps Pro active.
4. Network failure falls back to the existing 14-day offline grace after a recent successful validation.

Deactivation:
1. Study Boxes calls `POST /v1/licenses/deactivate` with `license_key` and `instance_id`.
2. Local license state is cleared even if the remote deactivation request fails.

## Error Handling

- Lemon Squeezy invalid, expired, disabled, wrong-product, or inactive responses map to `.invalid`.
- Malformed responses and transport failures map to `.error(...)`, with existing offline grace on validation.
- No study content, tasks, notes, URLs, app lists, file paths, or private API secrets are sent to Lemon Squeezy.

## Tests

- Parse successful activate/validate responses.
- Reject wrong product IDs.
- Reject inactive/expired/disabled license statuses.
- Confirm request bodies are form URL encoded.
- Confirm `LicenseManager` validates with the stored license key and instance ID.
- Confirm `LicenseView` has real purchase language through build verification.
