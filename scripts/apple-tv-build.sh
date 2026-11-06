#!/bin/bash
# Builds and signs Finesse for the Lounge Room Apple TV. Runs on fin-mac, fed over SSH:
#   ssh fin-mac 'bash -s' < scripts/apple-tv-build.sh           build and sign only
#   ssh fin-mac 'bash -s install' < scripts/apple-tv-build.sh   also install and launch
# Hold fin-mac-build and, for install, lounge-room-apple-tv. Other spokes build on this Mac,
# so the keychain search list changes only for signing, and the trap always restores it.
set -u
export PATH=/opt/homebrew/bin:$PATH
cd ~/Developer/Finesse || exit 1
UDID=00000000-0000000000000000
SHA=45CF62320027F92459D1D8905667A23B91A7466E
PROFILE="Finesse tvOS Development"
KEYCHAIN="$HOME/Library/Keychains/aisbuild.keychain-db"
APP=build/Build/Products/Debug-appletvos/Finesse.app
LOGS=$(mktemp -d /tmp/finesse-device.XXXXXX)
XCODE=(xcodebuild build -project Finesse.xcodeproj -scheme Finesse -destination "platform=tvOS,id=$UDID" -derivedDataPath build)

xcodegen generate >/dev/null || exit 3
# Compile first, so the search list is only changed for the short signing build.
"${XCODE[@]}" CODE_SIGNING_ALLOWED=NO > "$LOGS/unsigned.log" 2>&1 || { grep 'error:' "$LOGS/unsigned.log" | head -15; echo "unsigned build failed, log in $LOGS"; exit 4; }
echo "compiled"

others=$(pgrep -fl 'codesign|xcodebuild|productbuild|notarytool')
[ -z "$others" ] || { echo "Something else is building or signing, search list left alone:"; echo "$others" | cut -c1-120; exit 5; }

ORIGINAL=()
while IFS= read -r line; do line=${line#*\"}; ORIGINAL+=("${line%\"*}"); done < <(security list-keychains -d user)
[ ${#ORIGINAL[@]} -ge 1 ] || exit 6
restore() { security list-keychains -d user -s "${ORIGINAL[@]}"; security lock-keychain "$KEYCHAIN"; echo "search list restored"; }
trap restore EXIT
security list-keychains -d user -s "${ORIGINAL[@]}" "$KEYCHAIN"
security unlock-keychain -p "$(cat "$HOME/.aisbuild/keychain.pass")" "$KEYCHAIN" || exit 7

# The specifier resolves per target, because SwiftPM resource bundles refuse any profile.
"${XCODE[@]}" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=$SHA 'PROVISIONING_PROFILE_SPECIFIER=$(PP_$(WRAPPER_EXTENSION))' PP_app="$PROFILE" > "$LOGS/signed.log" 2>&1 || { grep 'error:' "$LOGS/signed.log" | head -15 | cut -c1-240; echo "signed build failed, log in $LOGS"; exit 8; }

# installd refuses a framework whose signing identifier differs from its bundle ID, and sign-on-copy keeps the old one.
resigned=0
for framework in "$APP"/Frameworks/*.framework; do
  bundle=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$framework/Info.plist")
  [ "$bundle" = "$(codesign -dvv "$framework" 2>&1 | sed -n 's/^Identifier=//p')" ] && continue
  codesign -f -s $SHA -i "$bundle" --timestamp=none "$framework" 2>/dev/null || exit 9
  resigned=$((resigned + 1))
done
if [ $resigned -gt 0 ]; then
  codesign -d --entitlements :- "$APP" > "$LOGS/app.entitlements" 2>/dev/null
  codesign -f -s $SHA --entitlements "$LOGS/app.entitlements" --timestamp=none "$APP" 2>/dev/null || exit 9
fi
codesign --verify --deep --strict "$APP" || exit 10
echo "signed, $resigned frameworks needed their identifier fixed"
restore; trap - EXIT
security list-keychains -d user

[ "${1:-}" = install ] || exit 0
xcrun devicectl device install app --device $UDID "$APP" < /dev/null 2>&1 | tail -6 | cut -c1-200
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 11
xcrun devicectl device process launch --terminate-existing --device $UDID au.com.athenanetworks.finesse < /dev/null 2>&1 | cut -c1-160
