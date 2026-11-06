#!/usr/bin/env python3
"""Turns each slice's installed dylibs into embeddable frameworks.

Each framework gets an @rpath install name, rewritten references to the others, an Info.plist, and a
privacy manifest made from what its binary actually imports. Usage: work dist deps_root deployment_target
"""
import glob
import os
import plistlib
import re
import shutil
import subprocess
import sys

work, dist, deps_root, target = sys.argv[1:5]
versions = dict(re.findall(r"^([A-Z0-9_]+)=(\S+)$", open(f"{deps_root}/versions.sh").read(), re.M))

# dylib name pattern, framework name, version
FRAMEWORKS = [
    (r"libavcodec(\.\d+)+\.dylib", "Libavcodec", versions["FFMPEG_VERSION"]),
    (r"libavfilter(\.\d+)+\.dylib", "Libavfilter", versions["FFMPEG_VERSION"]),
    (r"libavformat(\.\d+)+\.dylib", "Libavformat", versions["FFMPEG_VERSION"]),
    (r"libavutil(\.\d+)+\.dylib", "Libavutil", versions["FFMPEG_VERSION"]),
    (r"libswresample(\.\d+)+\.dylib", "Libswresample", versions["FFMPEG_VERSION"]),
    (r"libswscale(\.\d+)+\.dylib", "Libswscale", versions["FFMPEG_VERSION"]),
    (r"libmpv\.\d+\.dylib", "Libmpv", versions["MPV_TAG"].lstrip("v")),
    (r"libass\.\d+\.dylib", "Libass", versions["LIBASS_VERSION"]),
    (r"libfribidi\.\d+\.dylib", "Libfribidi", versions["FRIBIDI_VERSION"]),
    (r"libdav1d\.\d+\.dylib", "Libdav1d", versions["DAV1D_VERSION"]),
    (r"libplacebo\.\d+\.dylib", "Libplacebo", versions["LIBPLACEBO_TAG"].lstrip("v")),
    (r"libMoltenVK\.dylib", "MoltenVK", versions["MOLTENVK_TAG"].lstrip("v")),
    (r"libOpenSSL\.dylib", "OpenSSL", versions["OPENSSL_VERSION"]),
    (r"libuchardet(\.\d+)+\.dylib", "Libuchardet", versions["UCHARDET_VERSION"]),
]

# Symbol to (Apple category, approved reason). Only reasons that describe this code are listed.
REQUIRED_REASON = {
    "_stat": ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
    "_fstat": ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
    "_lstat": ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
    "_fstatat": ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
    "_getattrlist": ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
    "_fgetattrlist": ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
    "_mach_absolute_time": ("NSPrivacyAccessedAPICategorySystemBootTime", "35F9.1"),
}


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def imports(binary):
    names = set()
    for line in run("nm", "-u", binary).splitlines():
        names.add(line.strip().split("$")[0])
    return names


def privacy_manifest(binary):
    reasons = {}
    found = imports(binary)
    for symbol, (category, reason) in REQUIRED_REASON.items():
        if symbol in found:
            reasons.setdefault(category, set()).add(reason)
    return {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": category, "NSPrivacyAccessedAPITypeReasons": sorted(values)}
            for category, values in sorted(reasons.items())
        ],
    }


names = [name for _, name, _ in FRAMEWORKS]
for slice_name, platform in (("tvos", "AppleTVOS"), ("tvossim", "AppleTVSimulator")):
    lib = f"{work}/build/{slice_name}/prefix/lib"
    include = f"{work}/build/{slice_name}/prefix/include"
    files = {}
    for pattern, name, version in FRAMEWORKS:
        matches = [f for f in os.listdir(lib) if re.fullmatch(pattern, f) and not os.path.islink(f"{lib}/{f}")]
        assert len(matches) == 1, (pattern, matches, slice_name)
        files[name] = (matches[0], version)

    by_soname = {f: n for n, (f, _) in files.items()}
    for name, (dylib, version) in files.items():
        framework = f"{dist}/slices/{slice_name}/{name}.framework"
        os.makedirs(framework)
        binary = f"{framework}/{name}"
        shutil.copy2(f"{lib}/{dylib}", binary)
        os.chmod(binary, 0o755)
        run("install_name_tool", "-id", f"@rpath/{name}.framework/{name}", binary)
        for line in run("otool", "-L", binary).splitlines()[1:]:
            old = line.strip().split(" (")[0]
            base = os.path.basename(old)
            if base in by_soname:
                run("install_name_tool", "-change", old, f"@rpath/{by_soname[base]}.framework/{by_soname[base]}", binary)
            elif not old.startswith(("/usr/lib/", "/System/", "@rpath/Lib", "@rpath/MoltenVK", "@rpath/OpenSSL")):
                # A versioned symlink name still points at one of ours. Anything else is a build problem.
                match = next((n for n, (f, _) in files.items() if f.split(".")[0] == base.split(".")[0]), None)
                assert match, f"{name} depends on {old}"
                run("install_name_tool", "-change", old, f"@rpath/{match}.framework/{match}", binary)
        run("strip", "-x", binary)
        # Xcode keeps this identifier when it re-signs on copy, and a device refuses to install a
        # framework whose signing identifier differs from its bundle identifier. The simulator doesn't check.
        identifier = f"au.com.athenanetworks.finesse.deps.{name.lower()}"
        run("codesign", "-f", "-s", "-", "-i", identifier, binary)

        with open(f"{framework}/Info.plist", "wb") as f:
            plistlib.dump({
                "CFBundleDevelopmentRegion": "en",
                "CFBundleExecutable": name,
                "CFBundleIdentifier": identifier,
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": name,
                "CFBundlePackageType": "FMWK",
                "CFBundleShortVersionString": re.sub(r"[^0-9.]", "", version),
                "CFBundleVersion": "1",
                "CFBundleSupportedPlatforms": [platform],
                "MinimumOSVersion": target,
                "UIDeviceFamily": [3],
            }, f)
        with open(f"{framework}/PrivacyInfo.xcprivacy", "wb") as f:
            plistlib.dump(privacy_manifest(binary), f)

    # Only mpv's API is used from Swift, and the module keeps the same `import Libmpv` as MPVKit.
    libmpv = f"{dist}/slices/{slice_name}/Libmpv.framework"
    os.makedirs(f"{libmpv}/Headers")
    os.makedirs(f"{libmpv}/Modules")
    headers = sorted(glob.glob(f"{include}/mpv/*.h"))
    for header in headers:
        shutil.copy2(header, f"{libmpv}/Headers/")
    with open(f"{libmpv}/Modules/module.modulemap", "w") as f:
        f.write("framework module Libmpv {\n")
        for header in headers:
            f.write(f'    header "{os.path.basename(header)}"\n')
        f.write("    export *\n}\n")

with open(f"{dist}/frameworks.txt", "w") as f:
    f.write("\n".join(names) + "\n")
print("frameworks:", " ".join(names))
