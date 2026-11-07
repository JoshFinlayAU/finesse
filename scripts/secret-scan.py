"""Scans a simulator's Finesse containers for the test passwords and for access tokens. Run on the Mac.
Passwords come only from the environment, sent over SSH stdin. Prints counts and container-relative paths,
never a value. argv: simulator name, stage label, then any extra files or folders to use as positive controls.
"""
import base64
import glob
import json
import os
import plistlib
import re
import subprocess
import sys
import urllib.parse

SIM, LABEL, CONTROLS = sys.argv[1], sys.argv[2], sys.argv[3:]
OURS = "au.com.athenanetworks.finesse"


def variants(secret):
    """The forms a secret takes in a cache: raw, JSON-escaped, percent-encoded, UTF-16, base64."""
    raw = secret.encode()
    forms = {
        raw,
        json.dumps(secret)[1:-1].encode(),
        json.dumps(secret)[1:-1].replace("/", "\\/").encode(),
        urllib.parse.quote(secret, safe="").encode(),
        urllib.parse.quote_plus(secret).encode(),
        secret.encode("utf-16-le"),
        base64.b64encode(raw),
    }
    return [form for form in forms if len(form) >= 6]


PASSWORDS = [p for p in (os.environ.get("JELLYFIN_PASSWORD"), os.environ.get("JELLYFIN_PASSWORD_2")) if p]
if not PASSWORDS:
    sys.exit("no password in the environment")
PASSWORD_FORMS = [form for p in PASSWORDS for form in variants(p)]
# Jellyfin tokens are 32 hex digits. These are the ways one travels: header, query and JSON.
TOKEN = re.compile(
    rb'(?:Token="|ApiKey=|api_key=|X-Emby-Token[":\s]+|X-MediaBrowser-Token[":\s]+|"AccessToken"\s*:\s*")[0-9a-f]{32}'
    rb'|(?:T\x00o\x00k\x00e\x00n\x00=\x00"\x00|A\x00p\x00i\x00K\x00e\x00y\x00=\x00)(?:[0-9a-f]\x00){32}',
    re.IGNORECASE,
)

# The matcher has to find what it's looking for before a clean result means anything.
sample_token = b"Token=\"0123456789abcdef0123456789abcdef\""
for form in PASSWORD_FORMS:
    assert form in b"x" + form + b"y"
assert TOKEN.search(sample_token) and TOKEN.search(b"ApiKey=0123456789ABCDEF0123456789abcdef&")
assert TOKEN.search(sample_token.decode().encode("utf-16-le"))


def scan_file(path):
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return 0, 0
    passwords = sum(data.count(form) for form in PASSWORD_FORMS)
    tokens = len(TOKEN.findall(data))
    return passwords, tokens


def scan_tree(root, name):
    found = []
    files = 0
    for folder, _, names in os.walk(root):
        for file in names:
            path = os.path.join(folder, file)
            files += 1
            passwords, tokens = scan_file(path)
            if passwords or tokens:
                found.append((os.path.relpath(path, root), passwords, tokens))
    print(f"  {name}: {files} files, {len(found)} with secrets")
    for rel, passwords, tokens in found:
        print(f"    {rel}: password forms {passwords}, tokens {tokens}")
    return found


device = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]))
udid = next(d["udid"] for runtime in device["devices"].values() for d in runtime if d["name"] == SIM)
data = os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{udid}/data")

containers = {}
for metadata in glob.glob(f"{data}/Containers/*/*/*/.com.apple.mobile_container_manager.metadata.plist"):
    try:
        identifier = plistlib.load(open(metadata, "rb")).get("MCMMetadataIdentifier", "")
    except Exception:
        continue
    if identifier.startswith(OURS) or identifier.startswith("group." + OURS):
        kind = metadata.split("/Containers/")[1].split("/")[0:2]
        containers[f"{'/'.join(kind)} {identifier}"] = os.path.dirname(metadata)

print(f"== {LABEL}: {len(containers)} Finesse containers on {SIM}")
leaks = []
for name, root in sorted(containers.items()):
    found = scan_tree(root, name)
    if "xctrunner" not in name:
        leaks += found
keychain = glob.glob(f"{data}/Library/Keychains/*")
kc = [(os.path.basename(k), *scan_file(k)) for k in keychain]
print("  keychain files (tokens are meant to be here):", [(n, p, t) for n, p, t in kc if p or t] or "none with secrets")

for control in CONTROLS:
    if os.path.exists(control):
        hits = scan_tree(control, f"positive control {os.path.basename(control)}") if os.path.isdir(control) else [(control, *scan_file(control))]
        print(f"  positive control found secrets: {bool(hits and any(p or t for _, p, t in hits))}")
print(f"RESULT {LABEL}: {'LEAK' if leaks else 'clean'} in the app and extension containers")
