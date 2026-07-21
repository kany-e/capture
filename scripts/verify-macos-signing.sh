#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/Mema.app" >&2
  exit 64
fi

app_path="$1"
if [[ ! -d "$app_path" ]]; then
  echo "Mema app not found: $app_path" >&2
  exit 66
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

signing_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
team_identifier="$(
  print -r -- "$signing_details" |
    awk -F= '/^TeamIdentifier=/{print $2; exit}'
)"
designated_requirement="$(codesign -d -r- "$app_path" 2>&1)"

if [[ "$designated_requirement" == *"designated => cdhash "* ]]; then
  echo "Mema has a version-specific designated requirement." >&2
  exit 1
fi

if [[ -z "$team_identifier" || "$team_identifier" == "not set" ]]; then
  echo "Mema is ad-hoc signed; privacy permissions will not survive a rebuild." >&2
  exit 1
fi

echo "Stable Mema signing identity verified."
echo "TeamIdentifier=$team_identifier"
echo "Designated requirement is signer-based, not build-specific."
