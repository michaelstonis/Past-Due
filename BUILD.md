# Build, Signing, Notarization & Release Guide

This repository includes two scripts for semi-automated signing setup and local/CI packaging of **Past Due**:

- `scripts/setup_signing.sh` — Semi-automated wizard that detects your Apple Developer certificates & Team ID, generates/verifies your Sparkle 2 EdDSA keypair in the macOS Keychain, updates `SUPublicEDKey` in `Latest/Resources/Info.plist`, configures `xcrun notarytool` credentials, and writes a local gitignored `.signing.env` file.
- `scripts/build_dmg.sh` — Automatically manages semantic version and monotonic build numbers across `Latest.xcodeproj/project.pbxproj`, `Latest/Resources/Info.plist`, `CHANGELOG.md`, and `appcast.xml`; builds a universal (`arm64` + `x86_64`) `Past Due.app`; signs nested frameworks (`Sparkle.framework`) and the privileged helper (`PastDueUpdateInstaller`) inside-out; notarizes and staples the app and DMG; signs the DMG with Sparkle EdDSA; and optionally commits, tags, and publishes the GitHub Release (`--publish`).

---

## 1. Semi-Automated Signing & Notarization Setup (`scripts/setup_signing.sh`)

Run the interactive setup script once on your Mac:

```bash
./scripts/setup_signing.sh
```

What `scripts/setup_signing.sh` does:
1. **Checks your macOS Keychain** for a `Developer ID Application` certificate and auto-detects your Team ID (`A4P3DBPJT3`).
2. **Verifies or generates your Sparkle 2 EdDSA keypair** in your login Keychain (`generate_keys`) and automatically writes `SUPublicEDKey` into `Latest/Resources/Info.plist`.
3. **Configures Apple Notarization (`xcrun notarytool`)** under the keychain profile `PastDueNotary` using your Apple ID and an app-specific password from [account.apple.com](https://account.apple.com).
4. **Writes `.signing.env`** (ignored by git) so `scripts/build_dmg.sh` automatically uses your Team ID, signing identity, notary profile, Sparkle EdDSA key, and automatic version management (`AUTO_VERSION="1"`) on every build.
5. **Optional GitHub Actions sync**: Pass `--sync-github-secrets` to push `SPARKLE_PRIVATE_KEY`, `APPLE_TEAM_ID`, and `CODESIGN_IDENTITY` to `michaelstonis/Past-Due` via `gh secret set`.

---

## 2. Automatic Version Management (`scripts/build_dmg.sh`)

By default (`AUTO_VERSION=1`), `scripts/build_dmg.sh` manages both `MARKETING_VERSION` (`CFBundleShortVersionString`) and `CFBundleVersion` automatically:

- **Automatic Post-Tag Patch Bump**: If the current `MARKETING_VERSION` in `Latest.xcodeproj/project.pbxproj` (e.g. `1.0.0`) already has a matching git tag (`v1.0.0`) and new commits have been made since `v1.0.0`, running `./scripts/build_dmg.sh` automatically increments the patch version (`1.0.0` → `1.0.1`).
- **Explicit Semantic Version Bumping**:
  - `./scripts/build_dmg.sh --bump patch` (`1.0.0` → `1.0.1`)
  - `./scripts/build_dmg.sh --bump minor` (`1.0.0` → `1.1.0`)
  - `./scripts/build_dmg.sh --bump major` (`1.0.0` → `2.0.0`)
  - `./scripts/build_dmg.sh --version 1.2.3` (set explicit version)
- **Monotonic Build Number (`CFBundleVersion`)**: Automatically computes `max(git commit count, Info.plist CFBundleVersion, appcast.xml sparkle:version)` (and increments by `+1` whenever bumping versions on the same commit) and syncs it across `Latest/Resources/Info.plist`, the built `.app`, `.dSYM`, and `appcast.xml`.
- **Single-Command Release (`--publish`)**:
  ```bash
  ./scripts/build_dmg.sh --publish
  ```
  Builds, signs, notarizes, staples, updates `appcast.xml`, commits the version & appcast changes, creates and pushes git tag `v<version>`, and publishes the GitHub Release with `dist/Past-Due-<version>.dmg` and `dist/Past-Due-<version>.dmg.sha256`.

---

## 3. Useful Options

```bash
./scripts/build_dmg.sh --help
```

- `--bump <major|minor|patch>` — Bump semantic version across project, changelog, and appcast
- `--publish` — Commit version/appcast changes, tag `v<version>`, push to `origin/main`, and publish GitHub Release
- `--no-auto-version` — Disable automatic version bumping/syncing to source files
- `--app-only` — Build/sign/notarize only `dist/Past Due.app`
- `--skip-notarization` — Skip Apple notarization even if `NOTARY_PROFILE` is configured
- `--update-appcast` / `--no-update-appcast` — Enable or skip Sparkle EdDSA signing and `appcast.xml` update
- `--version <x.y.z>` / `--build <num>` — Explicitly set `CFBundleShortVersionString` / `CFBundleVersion`
- `--allow-debugging` — Add `com.apple.security.get-task-allow=true` when signing for local debugging
- `--open` — Reveal/open the resulting app or DMG when finished
