#!/bin/bash
# Usage: GALLERY_DIR=<dir> run.sh <testMethod> [reset]. Claims fin-mac-build for this one run, keeps only named g captures.
T=$1; RESET=$2; S=${GALLERY_DIR:?set GALLERY_DIR to a folder outside the repo}
cd ~/finesse
until aisandbox-agent claim fin-mac-build "agent-$AISANDBOX_AGENT: gallery capture, $T" >/dev/null 2>&1; do sleep 15; done
aisandbox-agent status | grep -q "claim: fin-mac-build by agent-$AISANDBOX_AGENT" || { echo "claim not held, stopping"; exit 1; }
rsync -az --delete --exclude-from=.rsyncignore ./ fin-mac:Developer/Finesse/
ssh fin-mac 'export PATH=/opt/homebrew/bin:$PATH; cd ~/Developer/Finesse && xcodegen generate -q; xcodebuild build-for-testing -project Finesse.xcodeproj -scheme Finesse -destination "platform=tvOS Simulator,name=Finesse Apple TV 4K" -derivedDataPath build 2>&1' | grep -E 'error:|TEST BUILD' | sed -E 's#/Users/USER/Developer/Finesse/##' | sort -u | cut -c1-220 | head -12
[ "$RESET" = reset ] && ssh fin-mac 'xcrun simctl boot "Finesse Apple TV 4K" 2>/dev/null; xcrun simctl bootstatus "Finesse Apple TV 4K" -b >/dev/null; xcrun simctl keychain "Finesse Apple TV 4K" reset'
ssh fin-mac 'rm -rf /tmp/finesse-gallery.xcresult /tmp/finesse-gallery-shots'
{ sed 's/^/TEST_RUNNER_/' .env.local; echo TEST_RUNNER_GALLERY_CAPTURE=1; } | ssh fin-mac "set -a; . /dev/stdin; set +a; cd ~/Developer/Finesse && xcodebuild test-without-building -project Finesse.xcodeproj -scheme Finesse -testPlan UI -only-testing:FinesseUITests/GalleryCaptureUITests/$T -destination 'platform=tvOS Simulator,name=Finesse Apple TV 4K' -derivedDataPath build -resultBundlePath /tmp/finesse-gallery.xcresult 2>&1" | grep -E 'error:|TEST (SUCC|FAIL)|Test Case .*(passed|failed)|skipped' | grep -v 'Type ' | sed -E 's#/Users/USER/Developer/Finesse/##' | sort -u | cut -c1-240 | head -14
ssh fin-mac 'mkdir -p /tmp/finesse-gallery-shots; xcrun xcresulttool export attachments --path /tmp/finesse-gallery.xcresult --output-path /tmp/finesse-gallery-shots >/dev/null 2>&1; python3 - <<P
import json,os,re
d="/tmp/finesse-gallery-shots"
keep=set()
for t in json.load(open(d+"/manifest.json")):
    for a in t.get("attachments",[]):
        n=a.get("suggestedHumanReadableName","").split("_")[0].rsplit(".",1)[0]
        if re.match(r"g\d\d-",n):
            os.replace(os.path.join(d,a["exportedFileName"]),os.path.join(d,n+".png")); keep.add(n+".png")
for f in os.listdir(d):
    if f not in keep: os.remove(os.path.join(d,f))
print("captured",sorted(keep))
P'
mkdir -p "$S/raw"; rsync -az fin-mac:/tmp/finesse-gallery-shots/ $S/raw/
ssh fin-mac 'rm -rf /tmp/finesse-gallery.xcresult /tmp/finesse-gallery-shots'
aisandbox-agent release fin-mac-build
