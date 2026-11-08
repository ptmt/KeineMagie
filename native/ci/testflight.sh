#!/bin/bash
# Only the protected GitHub main deployment job may invoke this script.
set +x
set -euo pipefail
umask 077
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REF:-}" == refs/heads/main ]] || {
  printf '%s\n' 'Signing/upload is restricted to GitHub Actions main.' >&2; exit 1;
}
case "${GITHUB_EVENT_NAME:-}" in push|workflow_dispatch) ;; *) exit 1 ;; esac
: "${RUNNER_TEMP:?}" "${GITHUB_ENV:?}"
: "${BUILD_CERTIFICATE_BASE64:?}" "${P12_PASSWORD:?}" "${BUILD_PROVISION_PROFILE_BASE64:?}"
: "${ASC_PRIVATE_KEY_BASE64:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"
[[ "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ && "$ASC_ISSUER_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  printf '%s\n' 'Invalid ASC key or issuer identifier format' >&2; exit 1;
}
repo="$(cd "$(dirname "$0")/../.." && pwd)"
root="$(mktemp -d "$RUNNER_TEMP/km-testflight.XXXXXXXX")"
touch "$root/owned-by-testflight"
printf 'TESTFLIGHT_TEMP=%s\n' "$root" >> "$GITHUB_ENV"
cleanup() { bash "$repo/native/ci/cleanup.sh" "$root"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Snapshot exactly, before changing the user's keychain search list.
security list-keychains -d user > "$root/keychains-quoted"
python3 - "$root" <<'PY'
import pathlib, shlex, sys
root = pathlib.Path(sys.argv[1])
paths = shlex.split((root / 'keychains-quoted').read_text())
(root / 'keychains-before').write_text(''.join(p + '\n' for p in paths))
PY
printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$root/distribution.p12"
printf '%s' "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode > "$root/profile.mobileprovision"
mkdir "$root/private_keys"
printf '%s' "$ASC_PRIVATE_KEY_BASE64" | base64 --decode > "$root/private_keys/AuthKey_${ASC_KEY_ID}.p8"
# Validate the API private key locally without printing any key material.
openssl pkey -in "$root/private_keys/AuthKey_${ASC_KEY_ID}.p8" -check -noout > /dev/null
security cms -D -i "$root/profile.mobileprovision" > "$root/profile.plist"
# Extract certificate only, never a private key. -legacy supports Keychain-exported PKCS#12.
openssl pkcs12 -legacy -in "$root/distribution.p12" -passin env:P12_PASSWORD -clcerts -nokeys -out "$root/cert.pem"
[[ "$(grep -c 'BEGIN CERTIFICATE' "$root/cert.pem")" == 1 ]] || {
  printf '%s\n' 'P12 must contain exactly one signing certificate' >&2; exit 1;
}
openssl x509 -in "$root/cert.pem" -checkend 0 -noout
openssl x509 -in "$root/cert.pem" -subject -nameopt RFC2253 -noout | sed 's/^subject= *//' > "$root/subject.txt"
openssl x509 -in "$root/cert.pem" -outform DER -out "$root/cert.der"
python3 "$repo/native/ci/signing_config.py" "$root"
uuid="$(< "$root/profile-uuid")"
fingerprint="$(< "$root/certificate-sha1")"
keychain="$root/signing.keychain-db"
printf '%s\n' "$keychain" > "$root/keychain-path"
password="$(openssl rand -hex 32)"
# Mask even the ephemeral password; never enable shell tracing.
printf '::add-mask::%s\n' "$password"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$root/distribution.p12" -P "$P12_PASSWORD" -k "$keychain" -t cert -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security > /dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$password" "$keychain" > /dev/null
keychains=()
while IFS= read -r path; do keychains+=("$path"); done < "$root/keychains-before"
security list-keychains -d user -s "$keychain" "${keychains[@]}"
# A valid identity proves the imported matching certificate has its private key
# and macOS accepts its validity/chain for code signing.
security find-identity -v -p codesigning "$keychain" > "$root/identities"
grep -F "$fingerprint" "$root/identities" > /dev/null || {
  printf '%s\n' 'No valid signing identity matching the profile certificate' >&2; exit 1;
}
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
profile="$profiles/km-$(basename "$root").mobileprovision"
[[ ! -e "$profile" ]] || exit 1
printf '%s\n' "$profile" > "$root/profile-path"
cp "$root/profile.mobileprovision" "$profile"
# Seconds-resolution UTC numbers are monotonic across serialized runs/reruns.
build="$(python3 "$repo/native/ci/signing_config.py" --build-number)"
printf 'Archiving build %s with manually validated signing\n' "$build"
xcodebuild -project "$repo/native/KeineMagie.xcodeproj" -scheme KeineMagie \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$root/KeineMagie.xcarchive" -derivedDataPath "$root/DerivedData" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=49PJNAT2WC \
  CODE_SIGN_IDENTITY="$fingerprint" PROVISIONING_PROFILE_SPECIFIER="$uuid" \
  OTHER_CODE_SIGN_FLAGS="--keychain $keychain" CURRENT_PROJECT_VERSION="$build" archive
xcodebuild -exportArchive -archivePath "$root/KeineMagie.xcarchive" \
  -exportOptionsPlist "$root/ExportOptions.plist" -exportPath "$root/export"
ipas=("$root/export/"*.ipa)
[[ ${#ipas[@]} == 1 && -f "${ipas[0]}" ]] || { printf '%s\n' 'Expected exactly one IPA' >&2; exit 1; }
export API_PRIVATE_KEYS_DIR="$root/private_keys"
# Xcode 26 uses legacy camelCase authentication flags; current altool uses kebab-case.
# Inspect the selected tool's help rather than assume the local Xcode is on CI.
xcrun altool --help > "$root/altool-help" 2>&1
if grep -q -- '--api-key' "$root/altool-help"; then
  auth=(--api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID")
  xcrun altool --validate-app "${ipas[0]}" "${auth[@]}"
  xcrun altool --upload-package "${ipas[0]}" "${auth[@]}"
else
  auth=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
  xcrun altool --validate-app -f "${ipas[0]}" -t ios "${auth[@]}"
  # Xcode 26's upload-package additionally requires numeric ASC app/provider IDs.
  # Its supported upload-app path needs only the requested API credentials.
  xcrun altool --upload-app -f "${ipas[0]}" -t ios "${auth[@]}"
fi
printf '%s\n' 'Apple upload command succeeded. Check App Store Connect processing and TestFlight availability.'
