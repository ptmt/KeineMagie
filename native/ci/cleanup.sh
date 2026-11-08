#!/bin/bash
# Shared by the signing process trap and the workflow's always() step.
set +x
set -euo pipefail
root="${1:-}"
[[ -n "$root" && -d "$root" ]] || exit 0
[[ "$(basename "$root")" == km-testflight.* && -f "$root/owned-by-testflight" ]] || {
  printf '%s\n' 'Refusing cleanup of unrecognized directory' >&2; exit 1;
}
status=0
if [[ -f "$root/keychains-before" ]]; then
  keychains=()
  while IFS= read -r path; do keychains+=("$path"); done < "$root/keychains-before"
  security list-keychains -d user -s "${keychains[@]}" || status=1
fi
if [[ -f "$root/keychain-path" ]]; then
  IFS= read -r keychain < "$root/keychain-path"
  if [[ "$keychain" == "$root/signing.keychain-db" && -f "$keychain" ]]; then
    security delete-keychain "$keychain" || status=1
  fi
fi
if [[ -f "$root/profile-install.json" ]]; then
  python3 "$(dirname "$0")/signing_config.py" --cleanup-profiles "$root" || status=1
fi
if [[ -f "$root/profile-path" ]]; then
  IFS= read -r profile < "$root/profile-path"
  expected="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/km-$(basename "$root").mobileprovision"
  if [[ "$profile" == "$expected" ]]; then rm -f -- "$profile" || status=1; else status=1; fi
fi
# Wipe sensitive files even if keychain restoration fails, but retain the small
# nonsecret recovery journal so the workflow's always() step can retry.
if [[ "$status" == 0 ]]; then
  rm -rf -- "$root"
else
  shopt -s dotglob nullglob
  for entry in "$root"/*; do
    case "$(basename "$entry")" in
      owned-by-testflight|keychains-before|keychain-path|profile-path|profile-install.json|signing.keychain-db) ;;
      *) rm -rf -- "$entry" ;;
    esac
  done
fi
exit "$status"
