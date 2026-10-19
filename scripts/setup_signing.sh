#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Latest/Resources/Info.plist"
SIGNING_ENV_FILE="${ROOT_DIR}/.signing.env"
SPARKLE_VERSION="2.10.0"
SPARKLE_TOOLS_DIR="${ROOT_DIR}/.build/sparkle-tools/${SPARKLE_VERSION}"

DEFAULT_TEAM_ID="A4P3DBPJT3"
DEFAULT_NOTARY_PROFILE="PastDueNotary"
SPARKLE_ACCOUNT="ed25519"
SYNC_GH_SECRETS=0
NON_INTERACTIVE=0

usage() {
  cat <<'USAGE'
Usage: scripts/setup_signing.sh [options]

Semi-automated local setup for Past Due code signing, Apple notarization,
and Sparkle EdDSA update signing.

Options:
  --team-id <TEAM_ID>          Apple Developer Team ID (default: auto-detected or A4P3DBPJT3)
  --notary-profile <NAME>      Keychain profile name for xcrun notarytool (default: PastDueNotary)
  --apple-id <EMAIL>           Apple ID email for notarytool store-credentials
  --sync-github-secrets        Push configured signing secrets to GitHub Actions via `gh secret set`
  --non-interactive            Do not prompt for interactive input; configure what is already available
  -h, --help                   Show this help
USAGE
}

TEAM_ID=""
NOTARY_PROFILE="${DEFAULT_NOTARY_PROFILE}"
APPLE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id)
      TEAM_ID="$2"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --apple-id)
      APPLE_ID="$2"
      shift 2
      ;;
    --sync-github-secrets)
      SYNC_GH_SECRETS=1
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

log_header() {
  printf '\n====================================================================\n'
  printf ' %s\n' "$*"
  printf '====================================================================\n'
}

ensure_sparkle_tools() {
  local derived_bin
  derived_bin="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" -print -quit 2>/dev/null || true)"
  if [[ -n "${derived_bin}" && -x "${derived_bin}" ]]; then
    SPARKLE_BIN_DIR="$(dirname "${derived_bin}")"
    return 0
  fi

  if [[ -x "${SPARKLE_TOOLS_DIR}/bin/generate_keys" ]]; then
    SPARKLE_BIN_DIR="${SPARKLE_TOOLS_DIR}/bin"
    return 0
  fi

  echo "Downloading Sparkle ${SPARKLE_VERSION} signing tools..."
  mkdir -p "${SPARKLE_TOOLS_DIR}"
  local archive="${SPARKLE_TOOLS_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o "${archive}"
  tar -xf "${archive}" -C "${SPARKLE_TOOLS_DIR}"
  SPARKLE_BIN_DIR="${SPARKLE_TOOLS_DIR}/bin"
}

# 1. Detect Code Signing Identity & Team ID
log_header "Step 1: Checking macOS Keychain for Code Signing Certificates"

IDENTITIES_OUTPUT="$(security find-identity -v -p codesigning 2>/dev/null || true)"
DEV_ID_APP="$(printf '%s\n' "${IDENTITIES_OUTPUT}" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
APPLE_DEV_ID="$(printf '%s\n' "${IDENTITIES_OUTPUT}" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"

if [[ -z "${TEAM_ID}" ]]; then
  if [[ -n "${DEV_ID_APP}" ]]; then
    TEAM_ID="$(printf '%s' "${DEV_ID_APP}" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')"
  fi
  if [[ -z "${TEAM_ID}" ]]; then
    TEAM_ID="${DEFAULT_TEAM_ID}"
  fi
fi

SELECTED_IDENTITY=""
if [[ -n "${DEV_ID_APP}" ]]; then
  echo "Found Developer ID Application certificate:"
  echo "  Identity: ${DEV_ID_APP}"
  echo "  Team ID:  ${TEAM_ID}"
  SELECTED_IDENTITY="${DEV_ID_APP}"
else
  echo "No 'Developer ID Application' certificate was found in your login Keychain."
  if [[ -n "${APPLE_DEV_ID}" ]]; then
    echo "Found local development identity: ${APPLE_DEV_ID}"
  fi
  cat <<EOF

To distribute a notarized macOS app outside the Mac App Store, Apple requires a
"Developer ID Application" certificate for Team ${TEAM_ID}:

  1. Open Xcode -> Settings (⌘,) -> Accounts
  2. Select your Apple ID and Team (${TEAM_ID}), then click "Manage Certificates..."
  3. Click "+" at the bottom-left and choose "Developer ID Application"

EOF
  if [[ "${NON_INTERACTIVE}" == "0" ]]; then
    read -r -p "Would you like to open Xcode now so you can create the certificate and press Enter when done? [y/N] " open_xcode
    if [[ "${open_xcode}" =~ ^[Yy]$ ]]; then
      open -a Xcode
      read -r -p "Press Enter after creating 'Developer ID Application' in Xcode -> Settings -> Accounts -> Manage Certificates..." _
      IDENTITIES_OUTPUT="$(security find-identity -v -p codesigning 2>/dev/null || true)"
      DEV_ID_APP="$(printf '%s\n' "${IDENTITIES_OUTPUT}" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
    fi
  fi

  if [[ -n "${DEV_ID_APP}" ]]; then
    echo "Detected new Developer ID Application certificate: ${DEV_ID_APP}"
    SELECTED_IDENTITY="${DEV_ID_APP}"
  elif [[ -n "${APPLE_DEV_ID}" ]]; then
    echo "Falling back to '${APPLE_DEV_ID}' for local development builds (notarization will be skipped until Developer ID Application is installed)."
    SELECTED_IDENTITY="${APPLE_DEV_ID}"
  else
    SELECTED_IDENTITY="-"
  fi
fi

# 2. Configure Sparkle EdDSA Keypair
log_header "Step 2: Verifying Sparkle 2 EdDSA Signing Key"

ensure_sparkle_tools
GENERATE_KEYS="${SPARKLE_BIN_DIR}/generate_keys"

SPARKLE_PUB_KEY="$("${GENERATE_KEYS}" --account "${SPARKLE_ACCOUNT}" -p 2>/dev/null || true)"
if [[ -z "${SPARKLE_PUB_KEY}" ]]; then
  echo "Generating new Sparkle EdDSA signing key in Keychain (account: ${SPARKLE_ACCOUNT})..."
  "${GENERATE_KEYS}" --account "${SPARKLE_ACCOUNT}"
  SPARKLE_PUB_KEY="$("${GENERATE_KEYS}" --account "${SPARKLE_ACCOUNT}" -p)"
fi

echo "Sparkle EdDSA Public Key: ${SPARKLE_PUB_KEY}"
plutil -replace SUPublicEDKey -string "${SPARKLE_PUB_KEY}" "${INFO_PLIST}"
echo "Updated SUPublicEDKey in Latest/Resources/Info.plist"

# 3. Configure Apple Notarization Profile (notarytool)
log_header "Step 3: Apple Notarization Keychain Profile (${NOTARY_PROFILE})"

NOTARY_READY=0
if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  echo "Keychain profile '${NOTARY_PROFILE}' is already configured and valid."
  NOTARY_READY=1
else
  echo "Keychain profile '${NOTARY_PROFILE}' is not yet stored in your macOS Keychain."
  if [[ "${NON_INTERACTIVE}" == "0" ]]; then
    read -r -p "Would you like to configure '${NOTARY_PROFILE}' now with an Apple app-specific password? [y/N] " setup_notary
    if [[ "${setup_notary}" =~ ^[Yy]$ ]]; then
      if [[ -z "${APPLE_ID}" ]]; then
        read -r -p "Enter your Apple ID email: " APPLE_ID
      fi
      echo "Tip: Create an app-specific password at https://account.apple.com -> Sign-In and Security -> App-Specific Passwords"
      xcrun notarytool store-credentials "${NOTARY_PROFILE}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${TEAM_ID}"
      NOTARY_READY=1
    fi
  else
    echo "Run interactively or execute:"
    echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id <your-apple-id> --team-id \"${TEAM_ID}\""
  fi
fi

# 4. Write .signing.env
log_header "Step 4: Writing Local Signing Configuration (.signing.env)"

cat > "${SIGNING_ENV_FILE}" <<EOF
# Auto-generated by scripts/setup_signing.sh (gitignored)
DEVELOPMENT_TEAM="${TEAM_ID}"
APP_SIGN_IDENTITY="${SELECTED_IDENTITY}"
NOTARY_PROFILE="${NOTARY_PROFILE}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT}"
UPDATE_APPCAST="1"
AUTO_VERSION="1"
EOF

if [[ "${NOTARY_READY}" == "0" || "${SELECTED_IDENTITY}" != Developer\ ID\ Application:* ]]; then
  echo 'SKIP_NOTARIZATION="1"' >> "${SIGNING_ENV_FILE}"
else
  echo 'SKIP_NOTARIZATION="0"' >> "${SIGNING_ENV_FILE}"
fi

chmod 600 "${SIGNING_ENV_FILE}"
echo "Saved local signing settings to ${SIGNING_ENV_FILE}"

# 5. Optional: Sync secrets to GitHub Actions
if [[ "${SYNC_GH_SECRETS}" == "1" ]]; then
  log_header "Step 5: Syncing Secrets to GitHub Actions (michaelstonis/Past-Due)"
  TMP_SPARKLE_DIR="$(mktemp -d)"
  TMP_SPARKLE_KEY="${TMP_SPARKLE_DIR}/sparkle_private_key"
  trap 'rm -rf "${TMP_SPARKLE_DIR}"' EXIT
  "${GENERATE_KEYS}" --account "${SPARKLE_ACCOUNT}" -x "${TMP_SPARKLE_KEY}"
  gh secret set SPARKLE_PRIVATE_KEY --repo michaelstonis/Past-Due < "${TMP_SPARKLE_KEY}"
  gh secret set APPLE_TEAM_ID --repo michaelstonis/Past-Due --body "${TEAM_ID}"
  gh secret set CODESIGN_IDENTITY --repo michaelstonis/Past-Due --body "${SELECTED_IDENTITY}"
  echo "Synced SPARKLE_PRIVATE_KEY, APPLE_TEAM_ID, and CODESIGN_IDENTITY to michaelstonis/Past-Due."
fi

log_header "Setup Summary"
echo "  Team ID:            ${TEAM_ID}"
echo "  Signing Identity:   ${SELECTED_IDENTITY}"
echo "  Sparkle Public Key: ${SPARKLE_PUB_KEY} (saved in Info.plist)"
echo "  Notary Profile:     ${NOTARY_PROFILE} (ready: ${NOTARY_READY})"
echo "  Config File:        ${SIGNING_ENV_FILE}"
echo ""
echo "You can now build, sign, notarize, and update appcast.xml with a single command:"
echo "  ./scripts/build_dmg.sh"
