#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-Release}"
build_dir="${EASYDEMO_DERIVED_DATA:-${TMPDIR:-/tmp}/EasyDemo-Personal-DerivedData}"
mkdir -p "$project_root/build"
identity_file="$project_root/build/signing-identity"
signing_identity="${EASYDEMO_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" && -f "$identity_file" ]]; then
  IFS= read -r signing_identity < "$identity_file"
fi
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(security find-identity -v -p codesigning | awk '/"/ {print $2; exit}')"
fi
signing_identity="${signing_identity:--}"
xcodebuild -project "$project_root/EasyDemo.xcodeproj" -scheme EasyDemo \
  -configuration "$configuration" -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$build_dir" \
  CODE_SIGNING_ALLOWED=NO build -quiet
app="$build_dir/Build/Products/$configuration/Cueframe.app"
codesign --force --sign "$signing_identity" --options runtime \
  --entitlements "$project_root/EasyDemo/EasyDemo.entitlements" "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$signing_identity" > "$identity_file"
if [[ "$signing_identity" == "-" ]]; then
  printf 'Ad-hoc build: macOS capture permissions may need renewal after rebuilding. Set EASYDEMO_SIGN_IDENTITY to a stable local signing certificate.\n'
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$project_root/build/Cueframe-Mac.zip"
if [[ "${1:-}" == "--install" ]]; then
  destination="$HOME/Applications/Cueframe.app"
  mkdir -p "$HOME/Applications"
  staging="$(mktemp -d "$HOME/Applications/.Cueframe-install.XXXXXX")"
  ditto "$app" "$staging/Cueframe.app"
  codesign --verify --deep --strict "$staging/Cueframe.app"
  previous="$destination"
  if [[ ! -e "$previous" && -d "$HOME/Applications/EasyDemo Personal.app" ]]; then
    previous="$HOME/Applications/EasyDemo Personal.app"
  fi
  backup=""
  if [[ -e "$previous" ]]; then
    expected_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
    previous_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$previous/Contents/Info.plist")"
    if [[ "$previous_id" != "$expected_id" ]]; then
      printf 'Cannot replace %s: it belongs to a different application.\n' "$previous" >&2
      exit 1
    fi
    mkdir -p "$project_root/build/previous-installations"
    backup_dir="$(mktemp -d "$project_root/build/previous-installations/Cueframe.XXXXXX")"
    backup="$backup_dir/Previous.app.backup"
    mv "$previous" "$backup"
  fi
  if ! mv "$staging/Cueframe.app" "$destination"; then
    if [[ -n "$backup" ]]; then mv "$backup" "$previous"; fi
    exit 1
  fi
  rmdir "$staging"
  codesign --verify --deep --strict "$destination"
  printf 'Installed: %s\n' "$destination"
fi
printf 'App: %s\nArchive: %s\n' "$app" "$project_root/build/Cueframe-Mac.zip"
