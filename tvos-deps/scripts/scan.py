#!/usr/bin/env python3
"""Scans built frameworks for what the App Store and our licence rule forbid. Exits non-zero on any failure.

Usage: scan.py <dist folder>, run on the Mac. Device and simulator slices are both checked.

Checks, per binary:
 - no fstatfs or other disk space APIs, which have no approved reason that describes this code
 - OpenSSL only in its own framework and used only by Libavformat, and no GnuTLS, nettle or GMP anywhere
 - every required-reason symbol it imports is declared in its privacy manifest
 - every Apple symbol it imports exists in the public SDK, as listed in the SDK's .tbd stubs
 - built for tvOS at the right deployment target, with @rpath install names
 - no GPL or nonfree build flags, and FFmpeg libraries report LGPL 3, the owner's decision for TLS 1.3
 - no local build paths in any file of the framework
"""
import glob
import os
import plistlib
import re
import subprocess
import sys

dist = sys.argv[1]
TARGET = "26.0"
DISK_SPACE = {"_statfs", "_fstatfs", "_statvfs", "_fstatvfs", "_getattrlistbulk", "_getmntinfo"}
TIMESTAMP = {"_stat", "_fstat", "_lstat", "_fstatat", "_getattrlist", "_fgetattrlist"}
BOOT_TIME = {"_mach_absolute_time"}
OPENSSL_SYMBOL = re.compile(r"^_(SSL_|SSL3_|TLS_|OPENSSL_|EVP_|BIO_|X509_)")
BANNED_CRYPTO = re.compile(r"^_(gnutls_|nettle_|__gmp|gmp_|mbedtls_)")
LICENCE_STRINGS = [b"--enable-gpl", b"--enable-nonfree", b"--enable-libx264", b"--enable-libx265"]
LOCAL_PATH = re.compile(rb"(?:/Users/|/Volumes/|/opt/homebrew|/Applications/Xcode|FinesseDeps|" + re.escape(os.path.realpath(dist)).encode() + rb")[^\0\s\"']{0,60}")
failures = []


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=False).stdout


def sdk_exports(sdk_name):
    """Every exported symbol in the public SDK, read from its .tbd stubs."""
    sdk = run("xcrun", "--sdk", sdk_name, "--show-sdk-path").decode().strip()
    symbols = set()
    stubs = glob.glob(f"{sdk}/usr/lib/**/*.tbd", recursive=True) + glob.glob(f"{sdk}/System/Library/Frameworks/**/*.tbd", recursive=True)
    for stub in stubs:
        text = open(stub, errors="ignore").read()
        for section, items in re.findall(r"(symbols|weak-symbols|thread-local-symbols|objc-classes|objc-eh-types|objc-ivars):\s*\[([^\]]*)\]", text):
            for raw in items.split(","):
                name = raw.strip().strip("'\"")
                if not name:
                    continue
                if section == "objc-classes":
                    symbols.update({f"_OBJC_CLASS_$_{name}", f"_OBJC_METACLASS_$_{name}"})
                elif section == "objc-eh-types":
                    symbols.add(f"_OBJC_EHTYPE_$_{name}")
                elif section == "objc-ivars":
                    symbols.add(f"_OBJC_IVAR_$_{name}")
                else:
                    symbols.add(name)
    return symbols


def fail(framework, message):
    failures.append(f"{framework}: {message}")
    print(f"  FAIL {message}")


own_frameworks = {}
for path in sorted(glob.glob(f"{dist}/*.xcframework")):
    own_frameworks[os.path.basename(path).split(".")[0]] = path

EXPECTED = {"Libmpv", "Libavcodec", "Libavfilter", "Libavformat", "Libavutil", "Libswresample", "Libswscale",
            "Libass", "Libfribidi", "Libdav1d", "Libplacebo", "MoltenVK", "OpenSSL", "Libuchardet"}
if set(own_frameworks) != EXPECTED:
    print(f"FAILED: expected {sorted(EXPECTED)}, found {sorted(own_frameworks)}")
    sys.exit(1)

scanned = 0
# platform is the number otool prints: 3 is tvOS, 8 is the tvOS simulator.
for variant, sdk_name, platform in (("tvos-arm64", "appletvos", "3"), ("tvos-arm64-simulator", "appletvsimulator", "8")):
    print(f"== {variant}")
    exports = sdk_exports(sdk_name)
    print(f"public SDK symbols read: {len(exports)}")
    provided = set()
    binaries = {}
    for name, path in own_frameworks.items():
        binary = f"{path}/{variant}/{name}.framework/{name}"
        binaries[name] = binary
        provided.update(line.split()[-1] for line in run("nm", "-gU", binary).decode().splitlines() if line.strip())

    for name, binary in binaries.items():
        print(f"{name}: {os.path.getsize(binary) // 1024} KB")
        scanned += 1
        framework = os.path.dirname(binary)
        undefined = {line.strip().split()[-1] for line in run("nm", "-u", binary).decode().splitlines() if line.strip()}
        plain = {symbol.split("$")[0] for symbol in undefined}
        defined = {line.split()[-1] for line in run("nm", "-gU", binary).decode().splitlines() if line.strip()}

        banned = plain & DISK_SPACE
        if banned:
            fail(name, f"disk space APIs imported: {sorted(banned)}")

        banned_crypto = sorted(s for s in defined | undefined if BANNED_CRYPTO.match(s))
        if banned_crypto:
            fail(name, f"GnuTLS, nettle, GMP or mbedTLS symbols: {banned_crypto[:6]}")
        if name != "OpenSSL":
            embedded = sorted(s for s in defined if OPENSSL_SYMBOL.match(s))
            if embedded:
                fail(name, f"OpenSSL code outside its framework: {embedded[:6]}")
            if name != "Libavformat" and any(OPENSSL_SYMBOL.match(s) for s in undefined):
                fail(name, "uses OpenSSL, and only Libavformat should")

        bundle_id = plistlib.load(open(f"{framework}/Info.plist", "rb"))["CFBundleIdentifier"]
        signed = subprocess.run(["codesign", "-dv", binary], capture_output=True, text=True).stderr
        signed_id = re.search(r"^Identifier=(.*)$", signed, re.M)
        if not signed_id or signed_id.group(1) != bundle_id:
            fail(name, f"signing identifier {signed_id.group(1) if signed_id else None} is not the bundle identifier {bundle_id}")

        manifest_path = f"{framework}/PrivacyInfo.xcprivacy"
        if not os.path.exists(manifest_path):
            fail(name, "no privacy manifest")
        else:
            declared = {e["NSPrivacyAccessedAPIType"] for e in plistlib.load(open(manifest_path, "rb"))["NSPrivacyAccessedAPITypes"]}
            if plain & TIMESTAMP and "NSPrivacyAccessedAPICategoryFileTimestamp" not in declared:
                fail(name, "imports file timestamp APIs without declaring them")
            if plain & BOOT_TIME and "NSPrivacyAccessedAPICategorySystemBootTime" not in declared:
                fail(name, "imports mach_absolute_time without declaring it")
            print(f"  manifest: {sorted(d.replace('NSPrivacyAccessedAPICategory', '') for d in declared) or 'nothing to declare'}")

        missing = sorted(s for s in undefined if s not in exports and s.split("$INODE64")[0] not in exports and s not in provided)
        # dyld and C++ runtime stubs are not always listed under the symbol spelling nm prints.
        missing = [s for s in missing if not s.startswith(("dyld_stub_binder", "__ZTI", "__ZTS", "__ZTV"))]
        if missing:
            fail(name, f"{len(missing)} imports not in the public SDK: {missing[:20]}")
        else:
            print(f"  all {len(undefined)} imports are public or ours")

        load = run("otool", "-l", binary).decode()
        build = re.search(r"LC_BUILD_VERSION.*?platform (\S+).*?minos ([\d.]+).*?sdk ([\d.]+)", load, re.S)
        if not build or build.group(1) != platform or build.group(2) != TARGET:
            fail(name, f"build version is {build.groups() if build else None}, wanted {platform} {TARGET}")
        else:
            print(f"  platform {build.group(1)}, minos {build.group(2)}, sdk {build.group(3)}")
        if not run("otool", "-D", binary).decode().splitlines()[-1].startswith(f"@rpath/{name}.framework/"):
            fail(name, "install name is not @rpath")
        for line in run("otool", "-L", binary).decode().splitlines()[1:]:
            dep = line.strip().split(" (")[0]
            if not dep.startswith(("/usr/lib/", "/System/Library/", "@rpath/Lib", "@rpath/MoltenVK", "@rpath/OpenSSL")):
                fail(name, f"unexpected dependency {dep}")

        data = open(binary, "rb").read()
        for flag in LICENCE_STRINGS:
            if flag in data:
                fail(name, f"contains {flag.decode()}")
        if name.startswith(("Libav", "Libsw")) and b"LGPL version 3 or later" not in data:
            fail(name, "does not report LGPL version 3 or later")
        for root, _, files in os.walk(framework):
            for file in files:
                path = os.path.join(root, file)
                found = sorted({m.group(0).decode(errors="replace") for m in LOCAL_PATH.finditer(open(path, "rb").read())})
                if found:
                    fail(name, f"local paths in {os.path.relpath(path, framework)}: {found[:4]}")
        for word in (b"dlopen", b"dlsym"):
            if f"_{word.decode()}".encode() in {s.encode() for s in plain}:
                print(f"  note: imports {word.decode()}")

if scanned != 2 * len(EXPECTED):
    failures.append(f"scanned {scanned} binaries, expected {2 * len(EXPECTED)}")
if failures:
    print(f"\nFAILED, {len(failures)} problems")
    for failure in failures:
        print(" -", failure)
    sys.exit(1)
print(f"\nPASSED, {scanned} binaries scanned")
