#!/bin/bash
# Builds a release of OpenDash Companion: a signed APK and the small file the
# app reads to tell whether a release is newer than itself. It does not
# publish anything.
#
# Usage: COMPANION_CERT_SHA256=<sha256 of the release certificate> scripts/release.sh <version>
#
# The certificate's SHA-256 is built into the app: it only installs an update
# of itself signed by that key. So the variable is required, and the build is
# refused when the APK is signed by anything else.
#
# It refuses to build when:
#   - <version> is not the version in pubspec.yaml;
#   - android/key.properties is missing (the build would be debug-signed);
#   - the working tree has uncommitted changes;
#   - the APK is not signed by COMPANION_CERT_SHA256.
#
# Output, in dist/:
#   opendash-companion-<version>.apk
#   companion-release.json   {version, build, apk, sha256, git_sha}
set -euo pipefail

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)\.[0-9]+)?$ ]] || { echo "Usage: COMPANION_CERT_SHA256=<sha256> scripts/release.sh <version>   (e.g. 0.1.0)"; exit 1; }
PIN="$(printf '%s' "${COMPANION_CERT_SHA256:-}" | tr -d ':' | tr 'A-F' 'a-f')"
[[ "$PIN" =~ ^[0-9a-f]{64}$ ]] || { echo "Refusing: COMPANION_CERT_SHA256 must be the release certificate's SHA-256 (64 hex digits)."; exit 1; }

cd "$(dirname "$0")/.."

PUBSPEC_VERSION="$(sed -n 's/^version: *\([0-9A-Za-z.-]*\).*/\1/p' pubspec.yaml | head -1)"
if [[ "$PUBSPEC_VERSION" != "$VERSION" ]]; then
  echo "Refusing: asked for $VERSION, but pubspec.yaml says $PUBSPEC_VERSION. Change it, commit, and run this again."
  exit 1
fi

if [[ ! -f android/key.properties ]]; then
  echo "Refusing: android/key.properties is missing, so the build would be signed with a debug key."
  echo "Create it with storeFile, storePassword, keyAlias and keyPassword for the release keystore."
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Refusing: there are uncommitted changes. A release is built from a commit."
  git status --short --untracked-files=no
  exit 1
fi

BUILD="$(git rev-list --count HEAD)"
GIT_SHA="$(git rev-parse --short HEAD)"
APK="opendash-companion-$VERSION.apk"

echo "=== Building OpenDash Companion $VERSION, build $BUILD, commit $GIT_SHA ==="
flutter build apk --release --build-number="$BUILD" \
  --dart-define=COMPANION_BUILD="$BUILD" --dart-define=COMPANION_VERSION="$VERSION" \
  --dart-define=COMPANION_CERT_SHA256="$PIN" \
  --dart-define=COMPANION_REPO="${COMPANION_REPO:-abhijithvijayan/opendash-companion}" \
  --dart-define=OPENDASH_REPO="${OPENDASH_REPO:-abhijithvijayan/opendash}" \
  --dart-define=OPENDASH_CERT_SHA256="${OPENDASH_CERT_SHA256:-25f012a33b86ab2365b480b594998a131fa8e0edc3768c9e258440f98d4ba7ee}"

mkdir -p dist
rm -f dist/opendash-companion-*.apk dist/companion-release.json
cp build/app/outputs/flutter-apk/app-release.apk "dist/$APK"

APKSIGNER="$(ls "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
if [[ -z "$APKSIGNER" ]]; then
  echo "Refusing: apksigner was not found (set ANDROID_HOME), so the signature could not be checked."
  rm -f "dist/$APK"
  exit 1
fi
CERTS="$("$APKSIGNER" verify --print-certs "dist/$APK")"
CERT="$(printf '%s\n' "$CERTS" | sed -n 's/^.*Signer.*certificate SHA-256 digest: //p' | sort -u)"
if [[ -z "$CERT" || "$(printf '%s\n' "$CERT" | wc -l)" -ne 1 ]]; then
  echo "Refusing: could not read one signing certificate from the APK."
  rm -f "dist/$APK"
  exit 1
fi
if printf '%s\n' "$CERTS" | grep -q 'CN=Android Debug'; then
  echo "Refusing: the APK is signed with a debug key. Check android/key.properties."
  rm -f "dist/$APK"
  exit 1
fi
if [[ "$CERT" != "$PIN" ]]; then
  echo "Refusing: the APK is signed by $CERT, not by COMPANION_CERT_SHA256 ($PIN)."
  echo "An app built this way could never update itself."
  rm -f "dist/$APK"
  exit 1
fi

SHA256="$(shasum -a 256 "dist/$APK" | cut -d' ' -f1)"
cat > dist/companion-release.json <<JSON
{ "version": "$VERSION", "build": $BUILD, "apk": "$APK",
  "sha256": "$SHA256", "git_sha": "$GIT_SHA" }
JSON

echo
echo "Built:"
echo "  dist/$APK"
echo "  dist/companion-release.json"
echo "Signed by (SHA-256 of the certificate): $CERT"
echo
echo "To publish:"
echo "  gh release create v$VERSION dist/$APK dist/companion-release.json --title \"OpenDash Companion $VERSION\" --notes-file <notes.md>"
