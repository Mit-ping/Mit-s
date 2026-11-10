# Beta signing and updates

The application ID stays `app.hiddify.com`. On 2026-11-10 the owner requested a new
permanent RSA-4096 signing key because the previous private key was unavailable.
The new keystore uses password-protected PKCS12. Only the public certificate SHA-256
is committed in `android/mit-signing-cert.sha256`; private backups and passwords
are delivered privately to the owner and must never be committed or uploaded to
GitHub release/Actions artifacts.

**This changes the signing identity.** An installed APK signed by the previous key
cannot be upgraded in place with this key. Android enforces this independently of
our update UI. Save original VLESS links and AmneziaWG exports before considering
a one-time reinstall; do not delete the installed app until those copies are safe.
The new APK cannot recover data removed by Android during uninstall. Subsequent
APKs signed with this same new key and a higher versionCode can upgrade in place
and preserve Android application data.
Keep the private keystore and passwords backed up privately: losing them prevents
future compatible upgrades. Never commit them or upload them to release artifacts.

Configure these GitHub Actions repository secrets once:

| Secret | Value |
| --- | --- |
| `ANDROID_SIGNING_KEY` | Base64 of the permanent PKCS12 `.keystore` file |
| `ANDROID_SIGNING_STORE_PASSWORD` | Keystore password |
| `ANDROID_SIGNING_KEY_PASSWORD` | Key password |
| `ANDROID_SIGNING_KEY_ALIAS` | `mits-vpn` |

The test job builds an explicitly unsigned release preview without signing secrets.
The publishing job downloads that same-run artifact, signs it, verifies the committed
certificate pin, package, version and non-debug mode, then creates an immutable GitHub
prerelease. Missing secrets fail publishing; no temporary debug signing fallback exists.
Version/tag/assets must be new for each release. Bump `MitRelease.buildName`,
`buildNumber`, label, workflow publishing branch/title and release notes together.

Release assets: `mits-vpn.apk`, `mits-vpn-update.json`, `SHA256SUMS`.
Updates are checked manually through the public GitHub releases API. HTTPS redirects
are restricted to explicit GitHub delivery hosts. Metadata and APK sizes are bounded;
only higher version codes for this package qualify. Android verifies SHA-256, size,
archive package/version and signing certificate match with the installed application
before both enabling installation and opening the system installer. The OS performs
its own APK signature verification. No silent installation or VPN auto-connect occurs.
Unknown-source permission is requested only after the user chooses installation.

The app cannot upgrade from an unsigned preview or another signing identity.
Keep GitHub account access and the four signing secrets protected; APK hash metadata
alone is not a substitute for a trusted signing certificate.


## Verified local signing of build 50006

The APK from Actions run `42784701948` passed the full test suite, native AWG
contract, release compilation and compiled launcher artwork checks. It was then
signed locally with the new key, without rebuilding or changing its application
payload. `apksigner` verified the signature and certificate pin; package/version,
16 KiB ZIP alignment and per-entry payload equality were checked. The signed
APK, update manifest, public certificate and verification receipt are separate
from the private owner backup.

The current GitHub job has no signing secrets. The owner must add the four
repository secrets above once to enable future CI signing. This does not require
posting the key or passwords in chat. Public update discovery still requires a
published canonical release with its signed APK and matching update manifest;
local files and Actions artifacts are not discovered by the app.
