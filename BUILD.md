# Build, Signing, Notarization & Release Guide

This repository includes two scripts for semi-automated signing setup and local/CI packaging of **Past Due**:

- `scripts/setup_signing.sh` — Semi-automated wizard that detects your Apple Developer certificates & Team ID, generates/verifies your Sparkle 2 EdDSA keypair in the macOS Keychain, updates `SUPublicEDKey` in `Latest/Resources/Info.plist`, configures `xcrun notarytool` credentials, and writes a local gitignored `.signing.env` file.
- `scripts/build_dmg.sh` — Builds a universal (`arm64` + `x86_64`) `Past Due.app`, signs nested frameworks (`Sparkle.framework`) and the privileged helper (`PastDueUpdateInstaller`) inside-out, notarizes and staples the app and DMG, signs the DMG with Sparkle EdDSA, and updates `appcast.xml`.

---

## 1. Semi-Automated Signing & Notarization Setup (`scripts/setup_signing.sh`)

Run the interactive setup script once on your Mac:

```bash
./scripts/setup_signing.sh
```

What `scripts/setup_signing.sh` does:
1. **Checks your macOS Keychain** for a `Developer ID Application` certificate and auto-detects your Team ID (`A4P3DBPJT3`).
   - If you don't yet have a `Developer ID Application` certificate installed locally, it can open Xcode for you (`Xcode -> Settings -> Accounts -> Manage Certificates... -> + -> Developer ID Application`) and wait until you create it.
2. **Verifies or generates your Sparkle 2 EdDSA keypair** in your login Keychain (`generate_keys`) and automatically writes `SUPublicEDKey` into `Latest/Resources/Info.plist`.
3. **Configures Apple Notarization (`xcrun notarytool`)** under the keychain profile `PastDueNotary` using your Apple ID and an app-specific password from [account.apple.com](https://account.apple.com).
4. **Writes `.signing.env`** (ignored by git) so `scripts/build_dmg.sh` automatically uses your Team ID, signing identity, notary profile, and Sparkle EdDSA key on every build.
5. **Optional GitHub Actions sync**: Pass `--sync-github-secrets` to push `SPARKLE_PRIVATE_KEY`, `APPLE_TEAM_ID`, and `CODESIGN_IDENTITY` to `michaelstonis/Past-Due` via `gh secret set`.

---

## 2. Building & Releasing (`scripts/build_dmg.sh`)

Once `.signing.env` is configured, running:

```bash
./scripts/build_dmg.sh
```

automatically:
- Builds a universal (`arm64` + `x86_64`) `Past Due.app` with `DEVELOPMENT_TEAM` embedded into `PastDueUpdateInstaller`
- Signs `Sparkle.framework`, `PastDueUpdateInstaller`, and `Past Due.app` inside-out with Hardened Runtime and secure timestamps
- Submits `Past Due.app` and `Past-Due-<version>.dmg` to Apple Notarization (`notarytool`) and staples the ticket (when `Developer ID Application` and `NOTARY_PROFILE` are active)
- Signs `dist/Past-Due-<version>.dmg` with your Sparkle EdDSA key (`sign_update`) and updates `appcast.xml` in-place
- Outputs `dist/Past Due.app`, `dist/Past-Due-<version>.dmg`, `.sha256` checksums, and `dist/Past-Due-<version>.build-manifest.json`

### Useful Options

```bash
./scripts/build_dmg.sh --help
```

- `--app-only` — Build/sign/notarize only `dist/Past Due.app`
- `--skip-notarization` — Skip Apple notarization even if `NOTARY_PROFILE` is configured
- `--update-appcast` / `--no-update-appcast` — Enable or skip Sparkle EdDSA signing and `appcast.xml` update
- `--version <x.y.z>` / `--build <num>` — Override `CFBundleShortVersionString` / `CFBundleVersion`
- `--allow-debugging` — Add `com.apple.security.get-task-allow=true` when signing for local debugging (cannot be combined with notarization)
- `--open` — Reveal/open the resulting app or DMG when finished
