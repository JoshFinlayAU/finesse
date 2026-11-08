#!/bin/bash
# Archives Finesse in Release and exports it for App Store Connect. Runs on fin-mac, fed over SSH:
#   ssh fin-mac 'bash -s' < scripts/app-store-archive.sh             archive, export and check
#   { echo "export ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id>"; cat scripts/app-store-archive.sh; } | ssh fin-mac 'bash -s validate'
#                                                                    also ask Apple to validate it
# The API key's .p8 goes in ~/.appstoreconnect/private_keys on the Mac. Its IDs stay out of the repo.
# It never uploads. The upload command it prints is for when the owner says go.
# Hold fin-mac-build. Other spokes build on this Mac, so the keychain search list changes only
# while signing, and the trap always restores it.
#
# Version and build number: MARKETING_VERSION (default 1.0), and FINESSE_BUILD_NUMBER, which
# defaults to the UTC time as YYYYMMDD.HHMM so each archive sorts above the last.
set -u
export PATH=/opt/homebrew/bin:$PATH
cd ~/Developer/Finesse || exit 1
VERSION=${MARKETING_VERSION:-1.0}
BUILD=${FINESSE_BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}
SHA=8ADCEE073C198B14F7F6D948464AAD4EB41F03B6   # Apple Distribution, in the aisbuild keychain
PROFILE="Finesse tvOS App Store"
EXTENSION_PROFILE="Finesse Top Shelf tvOS App Store"
KEYCHAIN="$HOME/Library/Keychains/aisbuild.keychain-db"
OUT=build/app-store/$VERSION-$BUILD
ARCHIVE=$OUT/Finesse.xcarchive
APP=$ARCHIVE/Products/Applications/Finesse.app
mkdir -p "$OUT" || exit 1
echo "version $VERSION build $BUILD, output in $OUT"

xcodegen generate >/dev/null || exit 3

# altool starts a 'log stream' that names it and can outlive it, so that doesn't count.
others=$(pgrep -fl 'codesign|xcodebuild|productbuild|notarytool|altool' | grep -v '/usr/bin/log stream')
[ -z "$others" ] || { echo "Something else is building or signing, search list left alone:"; echo "$others" | cut -c1-120; exit 5; }

ORIGINAL=()
while IFS= read -r line; do line=${line#*\"}; ORIGINAL+=("${line%\"*}"); done < <(security list-keychains -d user)
[ ${#ORIGINAL[@]} -ge 1 ] || exit 6
restore() { security list-keychains -d user -s "${ORIGINAL[@]}"; security lock-keychain "$KEYCHAIN"; echo "search list restored"; }
trap restore EXIT
security list-keychains -d user -s "${ORIGINAL[@]}" "$KEYCHAIN"
security unlock-keychain -p "$(cat "$HOME/.aisbuild/keychain.pass")" "$KEYCHAIN" || exit 7

# The specifier resolves per target, because SwiftPM resource bundles refuse any profile.
xcodebuild archive -project Finesse.xcodeproj -scheme Finesse -configuration Release \
  -destination generic/platform=tvOS -archivePath "$ARCHIVE" -derivedDataPath build/app-store/DerivedData \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=$SHA \
  'PROVISIONING_PROFILE_SPECIFIER=$(PP_$(WRAPPER_EXTENSION))' PP_app="$PROFILE" PP_appex="$EXTENSION_PROFILE" \
  > "$OUT/archive.log" 2>&1 || { grep 'error:' "$OUT/archive.log" | sort -u | head -15 | cut -c1-240; echo "archive failed, log in $OUT/archive.log"; exit 8; }
echo "archived"

# Signing on copy keeps our frameworks' ad-hoc identifiers, and Apple refuses an identifier that
# differs from the bundle ID. Fix them in the archive so the export starts from correct ones.
resigned=0
for framework in "$APP"/Frameworks/*.framework; do
  bundle=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$framework/Info.plist")
  [ "$bundle" = "$(codesign -dvv "$framework" 2>&1 | sed -n 's/^Identifier=//p')" ] && continue
  codesign -f -s $SHA -i "$bundle" --timestamp "$framework" 2>/dev/null || exit 9
  resigned=$((resigned + 1))
done
if [ $resigned -gt 0 ]; then
  codesign -d --entitlements :- "$APP" > "$OUT/app.entitlements" 2>/dev/null
  codesign -f -s $SHA --entitlements "$OUT/app.entitlements" --timestamp "$APP" 2>/dev/null || exit 9
fi
codesign --verify --deep --strict "$APP" || exit 10
echo "$resigned frameworks needed their identifier fixed"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>4S7BG5A4XV</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$SHA</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>au.com.athenanetworks.finesse</key><string>$PROFILE</string>
    <key>au.com.athenanetworks.finesse.TopShelf</key><string>$EXTENSION_PROFILE</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
# Packaging runs rsync, and Homebrew's rsync rejects the options Xcode passes to the system one.
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  > "$OUT/export.log" 2>&1 || { grep -iE 'error' "$OUT/export.log" | sort -u | head -15 | cut -c1-240; echo "export failed, log in $OUT/export.log"; exit 11; }
IPA=$(ls "$OUT"/export/*.ipa 2>/dev/null | head -1)
[ -n "$IPA" ] || { echo "no ipa in $OUT/export"; exit 11; }
restore; trap - EXIT
echo "exported $IPA"

# Checks on what Apple will receive, not on the archive.
CHECK=$(mktemp -d /tmp/finesse-ipa.XXXXXX)
ditto -x -k "$IPA" "$CHECK" || exit 12
A="$CHECK/Payload/Finesse.app"; E="$A/PlugIns/FinesseTopShelf.appex"
problems=0
problem() { echo "PROBLEM: $*"; problems=$((problems + 1)); }
plist() { /usr/libexec/PlistBuddy -c "Print $2" "$1/Info.plist" 2>/dev/null; }
for X in "$A" "$E"; do
  [ "$(plist "$X" CFBundleShortVersionString)" = "$VERSION" ] || problem "$(basename "$X") version is $(plist "$X" CFBundleShortVersionString)"
  [ "$(plist "$X" CFBundleVersion)" = "$BUILD" ] || problem "$(basename "$X") build is $(plist "$X" CFBundleVersion)"
  [ -f "$X/PrivacyInfo.xcprivacy" ] || problem "$(basename "$X") has no privacy manifest"
  codesign -d --entitlements :- "$X" 2>/dev/null > "$CHECK/ent.plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print get-task-allow' "$CHECK/ent.plist" 2>/dev/null)" = false ] || problem "$(basename "$X") is debuggable"
  codesign -dvv "$X" 2>&1 | grep -q '^Authority=Apple Distribution' || problem "$(basename "$X") is not signed for distribution"
  security cms -D -i "$X/embedded.mobileprovision" 2>/dev/null > "$CHECK/pp.plist"
  /usr/libexec/PlistBuddy -c 'Print ProvisionedDevices' "$CHECK/pp.plist" >/dev/null 2>&1 && problem "$(basename "$X") carries a device-limited profile"
done
count=0
for framework in "$A"/Frameworks/*.framework; do
  count=$((count + 1)); name=$(basename "$framework")
  [ "$(plist "$framework" CFBundleIdentifier)" = "$(codesign -dvv "$framework" 2>&1 | sed -n 's/^Identifier=//p')" ] || problem "$name signing identifier differs from its bundle ID"
  codesign -dvv "$framework" 2>&1 | grep -q '^Authority=Apple Distribution' || problem "$name is not signed for distribution"
  for key in MinimumOSVersion CFBundleShortVersionString CFBundleVersion CFBundleExecutable; do
    [ -n "$(plist "$framework" $key)" ] || problem "$name has no $key"
  done
  [ -f "$framework/PrivacyInfo.xcprivacy" ] || problem "$name has no privacy manifest"
done
echo "frameworks $count, MPVKit $(ls "$A/Frameworks" | grep -ci mpvkit)"
# Test-only modes are DEBUG-only and must not reach a Release binary.
leaks=$(strings -a "$A/Finesse" "$E/FinesseTopShelf" | grep -E -- '-Finesse[A-Z]|FINESSE-REMOTE|FINESSE_|ui-test-password' | sort -u)
[ -z "$leaks" ] || problem "debug-only strings in Release: $(echo $leaks | cut -c1-200)"
[ ! -e "$A/Finesse.debug.dylib" ] || problem "Finesse.debug.dylib is in the Release app"
dsyms=$(ls "$ARCHIVE/dSYMs" | tr '\n' ' ')
echo "dSYMs in archive: $dsyms"
missing=""
for framework in "$A"/Frameworks/*.framework; do
  case "$dsyms" in *"$(basename "$framework")"*) ;; *) missing="$missing$(basename "$framework" .framework) ";; esac
done
[ -z "$missing" ] || echo "no dSYM (an upload warning; crash logs show only exported symbols): $missing"
rm -rf "$CHECK"
echo "checks: $problems problem(s)"

UPLOAD="xcrun altool --upload-package \"\$HOME/Developer/Finesse/$IPA\" -t tvos --apiKey \"\$ASC_KEY_ID\" --apiIssuer \"\$ASC_ISSUER_ID\""
if [ "${1:-}" = validate ]; then
  [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] || { echo "validate needs ASC_KEY_ID and ASC_ISSUER_ID"; exit 13; }
  before=$(pgrep -f 'log stream --predicate process contains "altool"' | sort)
  xcrun altool --validate-app "$IPA" -t tvos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --output-format normal > "$OUT/validate.log" 2>&1
  status=$?
  # Stop only the log stream this validation started.
  for pid in $(comm -13 <(echo "$before") <(pgrep -f 'log stream --predicate process contains "altool"' | sort)); do kill "$pid"; done
  grep -vE '^\s*$|Running altool at path' "$OUT/validate.log" | cut -c1-300 | head -40
  echo "validate exit=$status"
fi
echo "to upload, when the owner says go: $UPLOAD"
[ $problems -eq 0 ]
