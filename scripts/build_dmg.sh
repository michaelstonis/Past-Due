#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Past Due"
ARTIFACT_SLUG="Past-Due"
PROJECT_NAME="Latest.xcodeproj"
PBXPROJ_FILE="Latest.xcodeproj/project.pbxproj"
SOURCE_INFO_PLIST="Latest/Resources/Info.plist"
CHANGELOG_FILE="CHANGELOG.md"
SCHEME_NAME="Latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
WORK_DIR="${ROOT_DIR}/.build/release-dmg"
DMG_STAGE_DIR="${WORK_DIR}/dmg-stage"
DERIVED_DATA_DIR="${WORK_DIR}/DerivedData"
DEFAULT_ENTITLEMENTS_FILE="${ROOT_DIR}/Latest/Resources/Latest.entitlements"
APPCAST_FILE="${ROOT_DIR}/appcast.xml"
SIGNING_ENV_FILE="${ROOT_DIR}/.signing.env"
SPARKLE_VERSION="2.10.0"
SPARKLE_TOOLS_DIR="${ROOT_DIR}/.build/sparkle-tools/${SPARKLE_VERSION}"

# Preserve any environment variables passed explicitly by caller before sourcing .signing.env
CALLER_DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
CALLER_APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
CALLER_NOTARY_PROFILE="${NOTARY_PROFILE:-}"
CALLER_SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-}"
CALLER_UPDATE_APPCAST="${UPDATE_APPCAST:-}"
CALLER_SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-}"
CALLER_AUTO_VERSION="${AUTO_VERSION:-}"

if [[ -f "${SIGNING_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${SIGNING_ENV_FILE}"
fi

DEVELOPMENT_TEAM="${CALLER_DEVELOPMENT_TEAM:-${DEVELOPMENT_TEAM:-}}"
APP_SIGN_IDENTITY="${CALLER_APP_SIGN_IDENTITY:-${APP_SIGN_IDENTITY:-}}"
NOTARY_PROFILE="${CALLER_NOTARY_PROFILE:-${NOTARY_PROFILE:-}}"
SKIP_NOTARIZATION="${CALLER_SKIP_NOTARIZATION:-${SKIP_NOTARIZATION:-0}}"
UPDATE_APPCAST="${CALLER_UPDATE_APPCAST:-${UPDATE_APPCAST:-0}}"
SPARKLE_ACCOUNT="${CALLER_SPARKLE_ACCOUNT:-${SPARKLE_ACCOUNT:-ed25519}}"
AUTO_VERSION="${CALLER_AUTO_VERSION:-${AUTO_VERSION:-1}}"

CONFIGURATION="${CONFIGURATION:-Release}"
XCODE_DESTINATION="${XCODE_DESTINATION:-generic/platform=macOS}"
VERSION_OVERRIDE="${APP_VERSION:-}"
BUILD_OVERRIDE="${APP_BUILD:-}"
BUMP_MODE="${BUMP_MODE:-}"
ENTITLEMENTS_SOURCE="${ENTITLEMENTS_FILE:-}"
ALLOW_DEBUGGING=0
APP_ONLY=0
OPEN_OUTPUT=0
PUBLISH_RELEASE=0

usage() {
  cat <<'USAGE'
Usage: scripts/build_dmg.sh [options]

Builds "Past Due.app" with xcodebuild, automatically manages semantic version
and build numbers across the project, signs & notarizes the app and DMG, and
updates appcast.xml.

Options:
  --bump <major|minor|patch>  Increment MARKETING_VERSION (e.g. 1.0.0 -> 1.0.1)
  --auto-version              Auto-bump patch if current version tag already exists (default)
  --no-auto-version           Do not auto-bump or write version changes back to source files
  --version <value>           Explicitly set CFBundleShortVersionString / MARKETING_VERSION
  --build <value>             Explicitly set CFBundleVersion (default: monotonic auto-increment)
  --publish                   Commit version/appcast updates, tag v<version>, push, and create GitHub Release
  --app-only                  Build/sign/notarize only the .app bundle
  --entitlements <path>       Entitlements file to use when signing
  --allow-debugging           Add com.apple.security.get-task-allow when signing
  --skip-notarization         Skip notarization/stapling even if NOTARY_PROFILE is set
  --update-appcast            Sign DMG with Sparkle EdDSA key and update appcast.xml
  --no-update-appcast         Skip Sparkle signing and appcast.xml update
  --configuration <name>      Xcode configuration to build (default: Release)
  --destination <dest>        xcodebuild destination (default: generic/platform=macOS)
  --open                      Open the resulting app or DMG when done
  -h, --help                  Show this help

Environment:
  AUTO_VERSION                Set to "1" (default) to automatically manage project version & build numbers.
  BUMP_MODE                   Same as --bump (major, minor, or patch).
  DEVELOPMENT_TEAM            Apple Developer Team ID (embedded in PastDueUpdateInstaller).
  APP_SIGN_IDENTITY           Optional signing identity. Use "-" for ad-hoc signing.
  NOTARY_PROFILE              notarytool keychain profile name for notarization.
  UPDATE_APPCAST              Set to "1" to sign DMG with Sparkle and update appcast.xml.
  SPARKLE_ACCOUNT             Keychain account for Sparkle EdDSA key (default: ed25519).
  APP_VERSION                 Same as --version.
  APP_BUILD                   Same as --build.

Examples:
  ./scripts/build_dmg.sh                        # Auto-manages version/build, signs, notarizes, updates appcast.xml
  ./scripts/build_dmg.sh --bump minor           # Bumps 1.0.0 -> 1.1.0, increments build number, builds & signs DMG
  ./scripts/build_dmg.sh --publish              # Builds, notarizes, commits appcast/version, tags & publishes GitHub Release
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      BUMP_MODE="$2"
      shift 2
      ;;
    --auto-version)
      AUTO_VERSION=1
      shift
      ;;
    --no-auto-version)
      AUTO_VERSION=0
      shift
      ;;
    --publish|--release)
      PUBLISH_RELEASE=1
      UPDATE_APPCAST=1
      shift
      ;;
    --app-only)
      APP_ONLY=1
      shift
      ;;
    --version)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --build)
      BUILD_OVERRIDE="$2"
      shift 2
      ;;
    --entitlements)
      ENTITLEMENTS_SOURCE="$2"
      shift 2
      ;;
    --allow-debugging)
      ALLOW_DEBUGGING=1
      shift
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION=1
      shift
      ;;
    --update-appcast)
      UPDATE_APPCAST=1
      shift
      ;;
    --no-update-appcast)
      UPDATE_APPCAST=0
      shift
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --destination)
      XCODE_DESTINATION="$2"
      shift 2
      ;;
    --open)
      OPEN_OUTPUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

log() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

plist_get() {
  plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}

plist_set() {
  local plist_file="$1"
  local key="$2"
  local value="$3"

  plutil -replace "${key}" -string "${value}" "${plist_file}" 2>/dev/null || \
    plutil -insert "${key}" -string "${value}" "${plist_file}"
}

plist_set_bool() {
  local plist_file="$1"
  local key="$2"
  local value="$3"

  plutil -replace "${key}" -bool "${value}" "${plist_file}" 2>/dev/null || \
    plutil -insert "${key}" -bool "${value}" "${plist_file}"
}

write_empty_plist() {
  local plist_file="$1"
  cat > "${plist_file}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF
}

bump_semver() {
  local current="$1"
  local mode="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "${current}"
  major="${major:-1}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  case "${mode}" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "Invalid --bump mode '${mode}'. Use major, minor, or patch." >&2
      exit 1
      ;;
  esac

  printf '%d.%d.%d' "${major}" "${minor}" "${patch}"
}

manage_project_version() {
  local pbxproj="${ROOT_DIR}/${PBXPROJ_FILE}"
  local src_plist="${ROOT_DIR}/${SOURCE_INFO_PLIST}"
  local changelog="${ROOT_DIR}/${CHANGELOG_FILE}"

  # Read current marketing version from project.pbxproj
  local current_marketing
  current_marketing="$(sed -n 's/.*MARKETING_VERSION = \([0-9][0-9.]*\);.*/\1/p' "${pbxproj}" | head -n 1)"
  current_marketing="${current_marketing:-1.0.0}"

  local target_marketing="${current_marketing}"
  if [[ -n "${VERSION_OVERRIDE}" ]]; then
    target_marketing="${VERSION_OVERRIDE}"
  elif [[ -n "${BUMP_MODE}" ]]; then
    target_marketing="$(bump_semver "${current_marketing}" "${BUMP_MODE}")"
  elif [[ "${AUTO_VERSION}" == "1" ]]; then
    # If tag v<current_marketing> already exists and HEAD has advanced past it, auto-bump patch
    if git -C "${ROOT_DIR}" rev-parse "v${current_marketing}" >/dev/null 2>&1; then
      local commits_since_tag
      commits_since_tag="$(git -C "${ROOT_DIR}" rev-list "v${current_marketing}..HEAD" --count 2>/dev/null || echo 0)"
      if [[ "${commits_since_tag}" -gt 0 ]]; then
        target_marketing="$(bump_semver "${current_marketing}" "patch")"
        log "Tag v${current_marketing} already exists with ${commits_since_tag} new commit(s); auto-bumping version to ${target_marketing}"
      fi
    fi
  fi

  # Compute monotonic build number (CFBundleVersion)
  local git_commits plist_build appcast_build max_build target_build
  git_commits="$(git -C "${ROOT_DIR}" rev-list HEAD --count 2>/dev/null || echo 1000)"
  plist_build="$(plist_get "${src_plist}" CFBundleVersion)"
  plist_build="${plist_build:-1000}"
  appcast_build="0"
  if [[ -f "${APPCAST_FILE}" ]]; then
    appcast_build="$(sed -n 's/.*<sparkle:version>\([0-9]*\)<\/sparkle:version>.*/\1/p' "${APPCAST_FILE}" | head -n 1)"
    appcast_build="${appcast_build:-0}"
  fi

  max_build="${git_commits}"
  if [[ "${plist_build}" =~ ^[0-9]+$ && "${plist_build}" -gt "${max_build}" ]]; then
    max_build="${plist_build}"
  fi
  if [[ "${appcast_build}" =~ ^[0-9]+$ && "${appcast_build}" -gt "${max_build}" ]]; then
    max_build="${appcast_build}"
  fi

  if [[ -n "${BUILD_OVERRIDE}" ]]; then
    target_build="${BUILD_OVERRIDE}"
  elif [[ -n "${BUMP_MODE}" || "${target_marketing}" != "${current_marketing}" ]]; then
    # Ensure a version bump always advances the build number beyond any previously recorded build
    if [[ "${git_commits}" -gt "${max_build}" ]]; then
      target_build="${git_commits}"
    else
      target_build=$((max_build + 1))
    fi
  else
    target_build="${max_build}"
  fi

  VERSION_OVERRIDE="${target_marketing}"
  BUILD_OVERRIDE="${target_build}"

  if [[ "${AUTO_VERSION}" == "1" || -n "${BUMP_MODE}" ]]; then
    log "Synchronizing project version: ${target_marketing} (build ${target_build})"
    python3 - "${pbxproj}" "${target_marketing}" <<'PY'
import re, sys
path, ver = sys.argv[1:]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
text = re.sub(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {ver};", text)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
    plist_set "${src_plist}" CFBundleVersion "${target_build}"

    if [[ -f "${changelog}" ]] && ! grep -q "^## Version ${target_marketing}" "${changelog}"; then
      python3 - "${changelog}" "${target_marketing}" <<'PY'
import sys
path, ver = sys.argv[1:]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
header = f"# Changelog\n\n## Version {ver}\n- Maintenance and stability improvements.\n"
if text.startswith("# Changelog"):
    text = text.replace("# Changelog\n", header, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
PY
    fi
  fi
}

ensure_sparkle_sign_update() {
  local derived_bin
  derived_bin="$(find "${DERIVED_DATA_DIR}" "${HOME}/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" -print -quit 2>/dev/null || true)"
  if [[ -n "${derived_bin}" && -x "${derived_bin}" ]]; then
    SIGN_UPDATE_BIN="${derived_bin}"
    return 0
  fi

  if [[ -x "${SPARKLE_TOOLS_DIR}/bin/sign_update" ]]; then
    SIGN_UPDATE_BIN="${SPARKLE_TOOLS_DIR}/bin/sign_update"
    return 0
  fi

  log "Downloading Sparkle ${SPARKLE_VERSION} tools for EdDSA signing"
  mkdir -p "${SPARKLE_TOOLS_DIR}"
  local archive="${SPARKLE_TOOLS_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o "${archive}"
  tar -xf "${archive}" -C "${SPARKLE_TOOLS_DIR}"
  SIGN_UPDATE_BIN="${SPARKLE_TOOLS_DIR}/bin/sign_update"
}

sign_nested_bundle() {
  local app_dir="$1"
  local identity="$2"
  local entitlements_file="$3"

  local base_args=(--force --sign "${identity}")
  if [[ "${identity}" != "-" ]]; then
    base_args+=(--timestamp --options runtime)
  fi

  # 1. Sign Sparkle.framework inside-out if present
  local sparkle_fw="${app_dir}/Contents/Frameworks/Sparkle.framework"
  if [[ -d "${sparkle_fw}" ]]; then
    for item in \
      "${sparkle_fw}/Versions/B/Autoupdate" \
      "${sparkle_fw}/Versions/B/Updater.app" \
      "${sparkle_fw}/Versions/B/XPCServices/Downloader.xpc" \
      "${sparkle_fw}/Versions/B/XPCServices/Installer.xpc"; do
      if [[ -e "${item}" ]]; then
        codesign "${base_args[@]}" "${item}"
      fi
    done
    codesign "${base_args[@]}" "${sparkle_fw}"
  fi

  # 2. Sign privileged XPC helper binary inside Contents/Resources
  local helper_bin="${app_dir}/Contents/Resources/PastDueUpdateInstaller"
  if [[ -f "${helper_bin}" ]]; then
    codesign "${base_args[@]}" -i "com.halfbuttonpress.PastDue.UpdateInstaller" "${helper_bin}"
  fi

  # 3. Sign main application bundle
  local app_args=("${base_args[@]}")
  if [[ -n "${entitlements_file}" ]]; then
    app_args+=(--entitlements "${entitlements_file}")
  fi
  codesign "${app_args[@]}" "${app_dir}"
}

write_manifest() {
  local manifest_file="$1"
  local dmg_name="$2"
  local dmg_sha="$3"
  local sparkle_sig="$4"

  {
    printf '{\n'
    printf '  "app_name": "%s",\n' "${APP_NAME}"
    printf '  "bundle_id": "%s",\n' "${BUNDLE_ID}"
    printf '  "version": "%s",\n' "${APP_VERSION}"
    printf '  "build": "%s",\n' "${APP_BUILD}"
    printf '  "configuration": "%s",\n' "${CONFIGURATION}"
    printf '  "architectures": "%s",\n' "${APP_ARCHS}"
    printf '  "development_team": "%s",\n' "${DEVELOPMENT_TEAM}"
    printf '  "app_signed": %s,\n' "${APP_SIGNED}"
    printf '  "app_notarized": %s,\n' "${APP_NOTARIZED}"
    printf '  "app_bundle": "%s",\n' "$(basename "${FINAL_APP}")"
    printf '  "app_executable_sha256": "%s"' "${APP_EXEC_SHA256}"
    if [[ -n "${dmg_name}" ]]; then
      printf ',\n  "dmg_file": "%s",\n' "${dmg_name}"
      printf '  "dmg_sha256": "%s"' "${dmg_sha}"
      if [[ -n "${sparkle_sig}" ]]; then
        printf ',\n  "sparkle_ed_signature": "%s"\n' "${sparkle_sig}"
      else
        printf '\n'
      fi
    else
      printf '\n'
    fi
    printf '}\n'
  } > "${manifest_file}"
}

require_cmd xcodebuild
require_cmd hdiutil
require_cmd shasum
require_cmd cp
require_cmd ln
require_cmd rm
require_cmd python3

APP_SIGNED=false
APP_NOTARIZED=false
DMG_SHA256=""
SPARKLE_ED_SIG=""
SIGN_ENTITLEMENTS_FILE=""
ARTIFACT_BASENAME="${ARTIFACT_SLUG}"

# Auto-extract DEVELOPMENT_TEAM from APP_SIGN_IDENTITY if not explicitly set
if [[ -z "${DEVELOPMENT_TEAM}" && -n "${APP_SIGN_IDENTITY}" && "${APP_SIGN_IDENTITY}" != "-" ]]; then
  DEVELOPMENT_TEAM="$(printf '%s' "${APP_SIGN_IDENTITY}" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')"
fi

if [[ -n "${NOTARY_PROFILE}" && "${SKIP_NOTARIZATION}" != "1" ]]; then
  if [[ -z "${APP_SIGN_IDENTITY}" || "${APP_SIGN_IDENTITY}" == "-" ]]; then
    echo "A real APP_SIGN_IDENTITY is required for notarization." >&2
    exit 1
  fi
  require_cmd ditto
  require_cmd xcrun
fi

if [[ -n "${APP_SIGN_IDENTITY}" ]]; then
  require_cmd codesign
fi

if [[ "${PUBLISH_RELEASE}" == "1" ]]; then
  require_cmd git
  require_cmd gh
fi

if [[ -z "${ENTITLEMENTS_SOURCE}" && -f "${DEFAULT_ENTITLEMENTS_FILE}" ]]; then
  ENTITLEMENTS_SOURCE="${DEFAULT_ENTITLEMENTS_FILE}"
fi

if [[ -n "${ENTITLEMENTS_SOURCE}" && ! -f "${ENTITLEMENTS_SOURCE}" ]]; then
  echo "Entitlements file not found: ${ENTITLEMENTS_SOURCE}" >&2
  exit 1
fi

if [[ "${ALLOW_DEBUGGING}" == "1" && -n "${NOTARY_PROFILE}" && "${SKIP_NOTARIZATION}" != "1" ]]; then
  echo "--allow-debugging cannot be combined with notarization." >&2
  echo "Use --skip-notarization or omit NOTARY_PROFILE for debug-signed builds." >&2
  exit 1
fi

if [[ "${OPEN_OUTPUT}" == "1" ]]; then
  require_cmd open
fi

# Synchronize and compute version + monotonic build number before building
manage_project_version

log "Cleaning previous artifacts"
rm -rf "${WORK_DIR}" "${DIST_DIR}"
mkdir -p "${WORK_DIR}" "${DIST_DIR}"

log "Building ${APP_NAME}.app with xcodebuild"
xcodebuild \
  -project "${ROOT_DIR}/${PROJECT_NAME}" \
  -scheme "${SCHEME_NAME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -destination "${XCODE_DESTINATION}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_DIR="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${APP_DIR}" ]]; then
  echo "Built app not found: ${APP_DIR}" >&2
  exit 1
fi

APP_PLIST="${APP_DIR}/Contents/Info.plist"
APP_BINARY="${APP_DIR}/Contents/MacOS/${APP_NAME}"
DSYM_PLIST="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app.dSYM/Contents/Info.plist"

if [[ -n "${VERSION_OVERRIDE}" ]]; then
  plist_set "${APP_PLIST}" CFBundleShortVersionString "${VERSION_OVERRIDE}"
fi

if [[ -n "${BUILD_OVERRIDE}" ]]; then
  plist_set "${APP_PLIST}" CFBundleVersion "${BUILD_OVERRIDE}"
  if [[ -f "${DSYM_PLIST}" ]]; then
    plist_set "${DSYM_PLIST}" CFBundleVersion "${BUILD_OVERRIDE}"
  fi
fi

APP_VERSION="$(plist_get "${APP_PLIST}" CFBundleShortVersionString)"
APP_BUILD="$(plist_get "${APP_PLIST}" CFBundleVersion)"
BUNDLE_ID="$(plist_get "${APP_PLIST}" CFBundleIdentifier)"
APP_ARCHS="$(lipo -archs "${APP_BINARY}" 2>/dev/null || true)"

if [[ -z "${APP_VERSION}" ]]; then
  APP_VERSION="unknown"
fi
if [[ -z "${APP_BUILD}" ]]; then
  APP_BUILD="unknown"
fi
if [[ -z "${BUNDLE_ID}" ]]; then
  BUNDLE_ID="unknown"
fi
if [[ -z "${APP_ARCHS}" ]]; then
  APP_ARCHS="unknown"
fi

ARTIFACT_BASENAME="${ARTIFACT_SLUG}-${APP_VERSION}"

if [[ -n "${APP_SIGN_IDENTITY}" ]]; then
  log "Signing app bundle (inside-out)"
  if [[ -n "${ENTITLEMENTS_SOURCE}" || "${ALLOW_DEBUGGING}" == "1" ]]; then
    SIGN_ENTITLEMENTS_FILE="${WORK_DIR}/${ARTIFACT_SLUG}.entitlements"
    if [[ -n "${ENTITLEMENTS_SOURCE}" ]]; then
      cp "${ENTITLEMENTS_SOURCE}" "${SIGN_ENTITLEMENTS_FILE}"
    else
      write_empty_plist "${SIGN_ENTITLEMENTS_FILE}"
    fi
    if [[ "${ALLOW_DEBUGGING}" == "1" ]]; then
      plist_set_bool "${SIGN_ENTITLEMENTS_FILE}" "com\\.apple\\.security\\.get-task-allow" true
    fi
  fi
  sign_nested_bundle "${APP_DIR}" "${APP_SIGN_IDENTITY}" "${SIGN_ENTITLEMENTS_FILE}"
  codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
  APP_SIGNED=true
fi

if [[ -n "${NOTARY_PROFILE}" && "${SKIP_NOTARIZATION}" != "1" ]]; then
  APP_ZIP="${WORK_DIR}/${ARTIFACT_SLUG}.zip"
  log "Creating zip for app notarization"
  ditto -c -k --keepParent "${APP_DIR}" "${APP_ZIP}"

  log "Submitting app for notarization"
  xcrun notarytool submit "${APP_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait

  log "Stapling notarization ticket to app"
  xcrun stapler staple "${APP_DIR}"
  xcrun stapler validate "${APP_DIR}"
  APP_NOTARIZED=true
fi

FINAL_APP="${DIST_DIR}/${APP_NAME}.app"
rm -rf "${FINAL_APP}"
cp -R "${APP_DIR}" "${FINAL_APP}"

APP_EXEC_SHA256="$(shasum -a 256 "${APP_BINARY}" | awk '{print $1}')"
APP_SHA_FILE="${DIST_DIR}/${ARTIFACT_BASENAME}.app-executable.sha256"
printf '%s  %s\n' "${APP_EXEC_SHA256}" "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" > "${APP_SHA_FILE}"

if [[ "${APP_ONLY}" == "1" ]]; then
  MANIFEST_FILE="${DIST_DIR}/${ARTIFACT_BASENAME}.build-manifest.json"
  write_manifest "${MANIFEST_FILE}" "" "" ""

  log "Done"
  echo "App: ${FINAL_APP}"
  echo "Version: ${APP_VERSION} (${APP_BUILD})"
  echo "App executable SHA256: ${APP_EXEC_SHA256}"
  echo "Checksum file: ${APP_SHA_FILE}"
  echo "Manifest: ${MANIFEST_FILE}"
  if [[ "${OPEN_OUTPUT}" == "1" ]]; then
    open "${FINAL_APP}"
  fi
  exit 0
fi

log "Preparing DMG staging folder"
mkdir -p "${DMG_STAGE_DIR}"
cp -R "${APP_DIR}" "${DMG_STAGE_DIR}/"
ln -s /Applications "${DMG_STAGE_DIR}/Applications"

UNSIGNED_DMG="${WORK_DIR}/${ARTIFACT_BASENAME}.dmg"
FINAL_DMG="${DIST_DIR}/${ARTIFACT_BASENAME}.dmg"

log "Building DMG"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGE_DIR}" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "${UNSIGNED_DMG}"

if [[ -n "${APP_SIGN_IDENTITY}" && "${APP_SIGN_IDENTITY}" != "-" ]]; then
  log "Signing DMG"
  codesign --force --timestamp --sign "${APP_SIGN_IDENTITY}" "${UNSIGNED_DMG}"
  codesign --verify --verbose=2 "${UNSIGNED_DMG}"
fi

if [[ -n "${NOTARY_PROFILE}" && "${SKIP_NOTARIZATION}" != "1" ]]; then
  log "Submitting DMG for notarization"
  xcrun notarytool submit "${UNSIGNED_DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait

  log "Stapling notarization ticket to DMG"
  xcrun stapler staple "${UNSIGNED_DMG}"
  xcrun stapler validate "${UNSIGNED_DMG}"
fi

mv -f "${UNSIGNED_DMG}" "${FINAL_DMG}"
DMG_SHA256="$(shasum -a 256 "${FINAL_DMG}" | awk '{print $1}')"
DMG_SHA_FILE="${FINAL_DMG}.sha256"
printf '%s  %s\n' "${DMG_SHA256}" "$(basename "${FINAL_DMG}")" > "${DMG_SHA_FILE}"

if [[ "${UPDATE_APPCAST}" == "1" && -f "${APPCAST_FILE}" ]]; then
  log "Signing DMG with Sparkle EdDSA key and updating appcast.xml"
  ensure_sparkle_sign_update
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    SIGN_OUTPUT="$(printf '%s\n' "${SPARKLE_PRIVATE_KEY}" | "${SIGN_UPDATE_BIN}" --ed-key-file - "${FINAL_DMG}" 2>/dev/null || true)"
  else
    SIGN_OUTPUT="$("${SIGN_UPDATE_BIN}" --account "${SPARKLE_ACCOUNT}" "${FINAL_DMG}" 2>/dev/null || true)"
  fi
  if [[ -n "${SIGN_OUTPUT}" ]]; then
    SPARKLE_ED_SIG="$(printf '%s' "${SIGN_OUTPUT}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    DMG_LENGTH="$(stat -f%z "${FINAL_DMG}")"
    PUB_DATE="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")"
    DOWNLOAD_URL="https://github.com/michaelstonis/Past-Due/releases/download/v${APP_VERSION}/$(basename "${FINAL_DMG}")"

    python3 - "${APPCAST_FILE}" "${APP_VERSION}" "${APP_BUILD}" "${PUB_DATE}" "${DOWNLOAD_URL}" "${SPARKLE_ED_SIG}" "${DMG_LENGTH}" <<'PY'
import re, sys

appcast_path, short_ver, build_ver, pub_date, url, ed_sig, length = sys.argv[1:]
with open(appcast_path, "r", encoding="utf-8") as f:
    content = f.read()

content = re.sub(r"<title>Version [^<]*</title>", f"<title>Version {short_ver}</title>", content, count=1)
content = re.sub(r"<pubDate>[^<]*</pubDate>", f"<pubDate>{pub_date}</pubDate>", content, count=1)
content = re.sub(r"<sparkle:version>[^<]*</sparkle:version>", f"<sparkle:version>{build_ver}</sparkle:version>", content, count=1)
content = re.sub(r"<sparkle:shortVersionString>[^<]*</sparkle:shortVersionString>", f"<sparkle:shortVersionString>{short_ver}</sparkle:shortVersionString>", content, count=1)
content = re.sub(r'url="[^"]*Past-Due-[^"]*\.dmg"', f'url="{url}"', content, count=1)
content = re.sub(r'sparkle:edSignature="[^"]*"', f'sparkle:edSignature="{ed_sig}"', content, count=1)
content = re.sub(r'length="[^"]*"', f'length="{length}"', content, count=1)

with open(appcast_path, "w", encoding="utf-8") as f:
    f.write(content)
PY
    echo "Updated ${APPCAST_FILE} for v${APP_VERSION} (${APP_BUILD}) with edSignature=${SPARKLE_ED_SIG} and length=${DMG_LENGTH}"
  else
    echo "Warning: Sparkle sign_update did not return a signature; appcast.xml was not modified." >&2
  fi
fi

MANIFEST_FILE="${DIST_DIR}/${ARTIFACT_BASENAME}.build-manifest.json"
write_manifest "${MANIFEST_FILE}" "$(basename "${FINAL_DMG}")" "${DMG_SHA256}" "${SPARKLE_ED_SIG}"

if [[ "${PUBLISH_RELEASE}" == "1" ]]; then
  log "Publishing v${APP_VERSION} (${APP_BUILD}) to GitHub"
  git -C "${ROOT_DIR}" add "${PBXPROJ_FILE}" "${SOURCE_INFO_PLIST}" "${APPCAST_FILE}" "${CHANGELOG_FILE}"
  if ! git -C "${ROOT_DIR}" diff --cached --quiet; then
    git -C "${ROOT_DIR}" commit -m "Release Past Due v${APP_VERSION} (${APP_BUILD})"
  fi
  if ! git -C "${ROOT_DIR}" rev-parse "v${APP_VERSION}" >/dev/null 2>&1; then
    git -C "${ROOT_DIR}" tag -a "v${APP_VERSION}" -m "Past Due ${APP_VERSION}"
  fi
  git -C "${ROOT_DIR}" push origin main --follow-tags
  if gh release view "v${APP_VERSION}" --repo michaelstonis/Past-Due >/dev/null 2>&1; then
    gh release upload "v${APP_VERSION}" "${FINAL_DMG}" "${DMG_SHA_FILE}" --clobber --repo michaelstonis/Past-Due
  else
    gh release create "v${APP_VERSION}" "${FINAL_DMG}" "${DMG_SHA_FILE}" \
      --repo michaelstonis/Past-Due \
      --title "Past Due ${APP_VERSION}" \
      --notes-file "${ROOT_DIR}/${CHANGELOG_FILE}"
  fi
fi

log "Done"
echo "Version: ${APP_VERSION} (Build ${APP_BUILD})"
echo "DMG: ${FINAL_DMG}"
echo "DMG SHA256: ${DMG_SHA256}"
if [[ -n "${SPARKLE_ED_SIG}" ]]; then
  echo "Sparkle edSignature: ${SPARKLE_ED_SIG}"
fi
echo "App executable SHA256: ${APP_EXEC_SHA256}"
echo "Checksum file: ${DMG_SHA_FILE}"
echo "Checksum file: ${APP_SHA_FILE}"
echo "Manifest: ${MANIFEST_FILE}"
if [[ "${OPEN_OUTPUT}" == "1" ]]; then
  open "${FINAL_DMG}"
fi
