# Instructions for coding agents — Mit VPN fork

This repository is a fork of **Hiddify**, a cross-platform Flutter client using the Hiddify core / sing-box. The product goal is a **one-tap Android VPN** with preconfigured split routing, followed by iOS and Windows. The user's existing Xray VLESS + REALITY backend must remain untouched unless a separate, explicit server-side task is approved.

## Read before making changes
- Read `docs/ONE_TAP_VPN_MVP_RU.md` and `docs/CODEX_ANDROID_KICKOFF_RU.md`.
- Inspect the **actual** entry points, state providers, connection UI, profile ingestion and route generation before changing any code. Do not assume path names. `lib/main.dart` is the dev entrypoint; `lib/main_prod.dart` is the production entrypoint. Keep them in sync where required.
- Respect SDK constraints in `pubspec.yaml` and existing build tooling. Do not replace the transport/VPN core with a homegrown cryptographic implementation.
- Keep platform-specific VPN permission, TUN/native extension and lifecycle logic intact. Implement the shared UX in Flutter where practical.

## Product contract
1. Android first. The primary screen shows connection state, a single connect/disconnect button, minimal diagnostics and an optional settings/help entry.
2. After **one-time activation** via a per-user secure HTTPS subscription, the user must not have to enter server address, UUID, SNI, Reality public key or rule lists manually.
3. Default routing: private/LAN addresses direct; Russian sites/IP ranges direct **as a best-effort policy**; other public destinations via the configured proxy, with updateable exceptions. Routing by geolocation/suffix is not perfect.
4. DNS must follow routing policy; do not allow an unintentional plaintext DNS fallback or an implicit direct fallback for foreign traffic if the VPN is unavailable. Make behavior explicit and test it.
5. Automatically refresh server profiles/rules securely, but **never** embed secret profiles or personal credentials in the public repository or APK defaults. No global shared access token.
6. Do not silently overwrite a user's existing profile/settings if migration is needed.

## Security and compliance
- NEVER commit real VDS IPs, hostnames tied to private infrastructure, REALITY private keys, VLESS UUIDs, short IDs, subscription tokens, Apple signing keys, keystores or personal information.
- Do not log authentication secrets or full subscription URLs. Scrub diagnostic export.
- Keep upstream copyright notices and comply with GPLv3 and third-party licenses. Do not reuse the upstream brand as the final product identity.
- Use platform-provided VPN/Network Extension APIs. Obtain required user permission and surface meaningful connection errors.
- No analytics, telemetry or arbitrary third-party network calls without explicit product decision.

## Implementation workflow
- Work in focused feature branches/PRs; don't commit directly to `main`.
- Before implementation, explain the components identified in this fork; then make incremental, testable changes.
- Prefer real unit/widget tests where available. On Android, test TUN VPN behavior on a device/emulator; build success alone is not proof that routing works.
- Avoid broad refactors. Preserve Windows/iOS buildability while implementing Android.
- Record manual validation steps and what was not tested in each PR.
- A working VPN or packaged release must **not** be claimed until a signed build connects to a test backend and route/DNS behavior is verified.
