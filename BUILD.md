# Build, Signing, Notarization & Release Guide

This repository includes two scripts and two GitHub Actions workflows for automated versioning, signing, notarization, and releases of **Past Due**:

- `.github/workflows/release.yml` — **Automated Build Server on `main`**: Every push to `main` automatically runs unit tests, manages semantic version & monotonic build numbers, signs & notarizes the universal app and DMG, signs the DMG with Sparkle EdDSA, commits the updated version/`appcast.xml` back to `main` (`[skip ci]`), tags `v<version>`, and publishes the GitHub Release.
- `.github/workflows/ci.yml` — Runs unit tests on pull requests and `develop` pushes.
- `scripts/setup_signing.sh` — Semi-automated wizard that detects your Apple Developer certificates & Team ID, generates/verifies your Sparkle 2 EdDSA keypair in the macOS Keychain, updates `SUPublicEDKey` in `Latest/Resources/Info.plist`, configures `xcrun notarytool` credentials, writes a local gitignored `.signing.env` file, and syncs all signing/notarization secrets to GitHub Actions (`--sync-github-secrets`).
- `scripts/build_dmg.sh` — Local/CI packaging script used by both local builds and GitHub Actions.

---

## 1. Automated Releases on Push to `main` (`.github/workflows/release.yml`)

Whenever a commit is pushed or merged to `main` (unless the commit message contains `[skip ci]`):

1. **Unit Tests**: Runs `xcodebuild test` across all 42 unit tests.
2. **Automatic Version & Build Number Management**:
   - **Initial Version**: If the current `MARKETING_VERSION` in `Latest.xcodeproj/project.pbxproj` (e.g. `1.0.0`) does not have a `v1.0.0` git tag yet, it releases `v1.0.0`.
   - **Subsequent Commits to `main`**: Once `v1.0.0` exists, pushing to `main` automatically bumps the version:
     - **Default**: Bumps **patch** (`1.0.0` → `1.0.1`)
     - **`feat: ...` or `[bump minor]` in commit message**: Bumps **minor** (`1.0.0` → `1.1.0`)
     - **`BREAKING CHANGE` or `[bump major]` in commit message**: Bumps **major** (`1.0.0` → `2.0.0`)
     - **Manual trigger (`workflow_dispatch`)**: Lets you pick `patch`, `minor`, or `major` from the GitHub Actions UI.
   - **Monotonic Build Number (`CFBundleVersion`)**: Automatically computes `max(git commit count, Info.plist CFBundleVersion, appcast.xml sparkle:version)` (or `+1` when bumping) and updates `Latest/Resources/Info.plist`, the built `.app`, `.dSYM`, and `appcast.xml`.
3. **Ephemeral Keychain Signing & Notarization**:
   - Imports `APPLE_CERTIFICATE_P12_BASE64` (`Developer ID Application`) into a temporary keychain on the GitHub Actions runner.
   - Configures `notarytool` (`APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`) and notarizes + staples both `Past Due.app` and `Past-Due-<version>.dmg`.
   - Imports `SPARKLE_PRIVATE_KEY`, signs the DMG with EdDSA (`sign_update`), and updates `appcast.xml`.
4. **Commit Back, Tag & GitHub Release**:
   - Commits the updated `Latest.xcodeproj/project.pbxproj`, `Latest/Resources/Info.plist`, `CHANGELOG.md`, and `appcast.xml` back to `main` with `chore(release): Past Due vX.Y.Z (Build N) [skip ci]`.
   - Tags `vX.Y.Z` and publishes the GitHub Release with `Past-Due-X.Y.Z.dmg`, `Past-Due-X.Y.Z.dmg.sha256`, and `Past-Due-X.Y.Z.build-manifest.json`.

---

## 2. Syncing Signing & Notarization Secrets to GitHub Actions

To enable full Developer ID signing and Apple Notarization on the GitHub Actions build server, run:

```bash
./scripts/setup_signing.sh --sync-github-secrets
```

This syncs the following repository secrets to `michaelstonis/Past-Due`:
- `SPARKLE_PRIVATE_KEY` — Sparkle 2 EdDSA private key exported from your Keychain
- `APPLE_TEAM_ID` — `A4P3DBPJT3`
- `CODESIGN_IDENTITY` — `Developer ID Application: Michael Stonis (A4P3DBPJT3)`
- `APPLE_CERTIFICATE_P12_BASE64` & `APPLE_CERTIFICATE_PASSWORD` — Ephemeral `.p12` export of your `Developer ID Application` certificate and private key (macOS Keychain will prompt for your Mac login password to allow exporting the key)
- `APPLE_ID` & `APPLE_APP_SPECIFIC_PASSWORD` — Apple ID email and app-specific password for `xcrun notarytool` on the CI runner

---

## 3. Local Builds & Manual Version Bumping (`scripts/build_dmg.sh`)

```bash
./scripts/build_dmg.sh                        # Auto-manages version/build, signs, notarizes, updates appcast.xml
./scripts/build_dmg.sh --bump minor           # Bumps 1.0.0 -> 1.1.0, increments build number, builds & signs DMG
./scripts/build_dmg.sh --publish              # Builds, notarizes, commits appcast/version, tags & publishes GitHub Release locally
```
