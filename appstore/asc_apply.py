#!/usr/bin/env python3
"""Enters the Finesse 1.0 listing into App Store Connect through its API, in one go.

Usage:
  python3 appstore/asc_apply.py plan                 prints every request, offline, with no network use
  python3 appstore/asc_apply.py apply --yes          sends them. Only after the owner's go-ahead
  python3 appstore/asc_apply.py encryption --build <build id> --yes   after a build is uploaded

Text comes from the asc:<field> blocks in metadata.md, review-notes.md and eula.md, so there is one
copy of every string. Screenshots come from --screenshots <folder> (default: FINESSE_SCREENSHOTS).

Credentials stay out of the repo: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8, default
~/.appstoreconnect/private_keys/AuthKey_<key id>.p8). Review contact: ASC_REVIEW_FIRST_NAME,
ASC_REVIEW_LAST_NAME, ASC_REVIEW_PHONE, ASC_REVIEW_EMAIL. Needs the `cryptography` package for apply.

App Privacy answers have no API, so they are a manual step. See asc-api.md.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

APP_ID = "6832351387"          # Finesse, from App Store Connect
LOCALE = "en-AU"
VERSION = "1.0"
PLATFORM = "TV_OS"
BASE_TERRITORY = "AUS"
EXCLUDED_TERRITORIES = {"FRA"}  # owner, 2026-11-09: no French encryption declaration
SCREENSHOT_ORDER = [            # see screenshots.md
    "as-04-home-row", "as-05-movies", "as-08-detail", "as-10-bar", "as-11-info",
    "as-07-search", "as-02-user-picker", "as-01-server-entry",
]
AGE_RATING = {                  # see age-rating.md, every answer for the app itself
    **{k: "NONE" for k in [
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
        "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
        "sexualContentOrNudity", "horrorOrFearThemes", "matureOrSuggestiveThemes",
        "violenceCartoonOrFantasy", "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic"]},
    **{k: False for k in [
        "advertising", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
        "parentalControls", "ageAssurance", "socialMedia", "unrestrictedWebAccess", "userGeneratedContent"]},
    "ageRatingOverrideV2": "NONE",
}
ENCRYPTION_DESCRIPTION = (
    "HTTPS through Apple's URLSession, and OpenSSL 3.5 (standard TLS 1.2 and 1.3) inside the bundled "
    "FFmpeg library for streams the built-in player fetches. No proprietary algorithms."
)

HERE = Path(__file__).resolve().parent
API = "https://api.appstoreconnect.apple.com"


def block(file, name):
    text = (HERE / file).read_text()
    found = re.search(r"<!-- asc:%s -->\n```\n(.*?)\n```" % re.escape(name), text, re.S)
    if not found:
        sys.exit(f"no asc:{name} block in {file}")
    return found.group(1)


def eula_text():
    text = (HERE / "eula.md").read_text()
    body = text.split("\n---\n")[1].strip()
    body = re.sub(r" ?\[Apple term \d+\]", "", body)
    if "OWNER TO" in body:
        return None
    return body


class Client:
    def __init__(self, live):
        self.live = live
        self.token, self.made = None, 0
        self.fake = 0

    def jwt(self):
        if self.token and time.time() - self.made < 900:
            return self.token
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec, utils
        key_id, issuer = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
        path = os.environ.get("ASC_KEY_PATH") or os.path.expanduser(
            f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
        key = serialization.load_pem_private_key(Path(path).read_bytes(), password=None)
        enc = lambda d: base64.urlsafe_b64encode(json.dumps(d, separators=(",", ":")).encode()).rstrip(b"=")
        now = int(time.time())
        head = enc({"alg": "ES256", "kid": key_id, "typ": "JWT"})
        claims = enc({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"})
        signed = key.sign(head + b"." + claims, ec.ECDSA(hashes.SHA256()))
        r, s = utils.decode_dss_signature(signed)
        sig = base64.urlsafe_b64encode(r.to_bytes(32, "big") + s.to_bytes(32, "big")).rstrip(b"=")
        self.token, self.made = (head + b"." + claims + b"." + sig).decode(), now
        return self.token

    def call(self, method, path, body=None, note=""):
        if not self.live:
            print(f"\n{method} {path}" + (f"    # {note}" if note else ""))
            if body is not None:
                print(json.dumps(body, indent=2, ensure_ascii=False)[:1500])
            self.fake += 1
            return {"data": {"id": f"<{note or path.split('/')[2]}>", "attributes": {}}, "_planned": True}
        request = urllib.request.Request(API + path, method=method,
                                         data=None if body is None else json.dumps(body).encode())
        request.add_header("Authorization", "Bearer " + self.jwt())
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            sys.exit(f"{method} {path} failed: {error.code} {error.read().decode()[:600]}")
        print(f"{method} {path}: ok")
        return json.loads(raw) if raw else {}

    def get_all(self, path):
        if not self.live:
            self.call("GET", path)
            return []
        items, url = [], path
        while url:
            page = self.call("GET", url)
            items += page.get("data", [])
            nxt = page.get("links", {}).get("next")
            url = nxt[len(API):] if nxt else None
        return items


def ref(kind, id):
    return {"data": {"type": kind, "id": id}}


def one(client, path, note, pick=lambda items: items[0] if items else None):
    if not client.live:
        client.call("GET", path, note=note)
        return {"id": f"<{note}>", "attributes": {}}
    found = pick(client.get_all(path))
    if not found:
        sys.exit(f"nothing found at {path}")
    return found


def listing(client):
    live_states = ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE")
    app_info = one(client, f"/v1/apps/{APP_ID}/appInfos", "appInfo being prepared",
                   lambda items: next((i for i in items if (i["attributes"].get("state") or
                                       i["attributes"].get("appStoreState")) not in live_states), None))
    info_loc = one(client, f"/v1/appInfos/{app_info['id']}/appInfoLocalizations", f"appInfoLocalization {LOCALE}",
                   lambda items: next((i for i in items if i["attributes"]["locale"] == LOCALE), None))

    # 1. Subtitle and privacy policy URL (the name is already Finesse).
    client.call("PATCH", f"/v1/appInfoLocalizations/{info_loc['id']}", {"data": {
        "type": "appInfoLocalizations", "id": info_loc["id"], "attributes": {
            "subtitle": block("metadata.md", "subtitle"),
            "privacyPolicyUrl": block("metadata.md", "privacyPolicyUrl")}}}, "1 subtitle, privacy URL")

    # 2. Category.
    client.call("PATCH", f"/v1/appInfos/{app_info['id']}", {"data": {
        "type": "appInfos", "id": app_info["id"], "relationships": {
            "primaryCategory": ref("appCategories", "ENTERTAINMENT")}}}, "2 category")

    # 3. Age rating.
    path = f"/v1/appInfos/{app_info['id']}/ageRatingDeclaration"
    rating = client.call("GET", path, note="ageRatingDeclaration")["data"]
    client.call("PATCH", f"/v1/ageRatingDeclarations/{rating['id']}", {"data": {
        "type": "ageRatingDeclarations", "id": rating["id"], "attributes": AGE_RATING}}, "3 age rating 4+")

    # 4. Copyright and release type on version 1.0.
    version = one(client, f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]={PLATFORM}"
                          f"&filter[versionString]={VERSION}", f"appStoreVersion {VERSION}")
    client.call("PATCH", f"/v1/appStoreVersions/{version['id']}", {"data": {
        "type": "appStoreVersions", "id": version["id"], "attributes": {
            "copyright": block("metadata.md", "copyright"), "releaseType": "MANUAL"}}}, "4 copyright")

    # 5. Description, keywords, promotional text, support URL. No marketing URL for 1.0.
    version_loc = one(client, f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                      f"appStoreVersionLocalization {LOCALE}",
                      lambda items: next((i for i in items if i["attributes"]["locale"] == LOCALE), None))
    client.call("PATCH", f"/v1/appStoreVersionLocalizations/{version_loc['id']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": version_loc["id"], "attributes": {
            "description": block("metadata.md", "description"),
            "keywords": block("metadata.md", "keywords"),
            "promotionalText": block("metadata.md", "promotionalText"),
            "supportUrl": block("metadata.md", "supportUrl")}}}, "5 description and keywords")
    return app_info, version, version_loc


def review_details(client, version):
    # 6. App Review information: contact, demo account and notes.
    names = ["ASC_REVIEW_FIRST_NAME", "ASC_REVIEW_LAST_NAME", "ASC_REVIEW_PHONE", "ASC_REVIEW_EMAIL"]
    missing = [n for n in names if not os.environ.get(n)]
    if missing and client.live:
        sys.exit("review contact not set: " + ", ".join(missing))
    attributes = {
        "contactFirstName": os.environ.get(names[0], "<first name>"),
        "contactLastName": os.environ.get(names[1], "<last name>"),
        "contactPhone": os.environ.get(names[2], "<phone>"),
        "contactEmail": os.environ.get(names[3], "<email>"),
        "demoAccountRequired": True, "demoAccountName": "demo", "demoAccountPassword": "",
        "notes": block("review-notes.md", "reviewNotes")}
    existing = None
    if client.live:
        try:
            existing = client.call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
        except SystemExit:
            existing = None
    else:
        client.call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail", note="review detail, if any")
    if existing:
        client.call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": existing["id"], "attributes": attributes}}, "6 review details")
    else:
        client.call("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attributes,
            "relationships": {"appStoreVersion": ref("appStoreVersions", version["id"])}}},
            "6 review details (POST if none yet, PATCH otherwise)")


def availability_and_price(client):
    territories = [t["id"] for t in client.get_all("/v1/territories?limit=200")] if client.live else ["<each of ~175>"]
    sold = [t for t in territories if t not in EXCLUDED_TERRITORIES]

    # 7. Availability: every territory except France, and not new ones automatically.
    included = [{"type": "territoryAvailabilities", "id": f"${{{t}}}",
                 "attributes": {"available": t not in EXCLUDED_TERRITORIES},
                 "relationships": {"territory": ref("territories", t)}}
                for t in territories + (["FRA"] if not client.live else [])]
    client.call("POST", "/v2/appAvailabilities", {"data": {
        "type": "appAvailabilities", "attributes": {"availableInNewTerritories": False},
        "relationships": {"app": ref("apps", APP_ID), "territoryAvailabilities": {
            "data": [{"type": "territoryAvailabilities", "id": i["id"]} for i in included]}}},
        "included": included}, "7 availability, all but FRA. If it already exists, PATCH FRA's territoryAvailability instead")

    # 8. Price: free, from the base territory.
    if client.live:
        points = client.get_all(f"/v1/apps/{APP_ID}/appPricePoints?filter[territory]={BASE_TERRITORY}&limit=200")
        free = next(p["id"] for p in points if float(p["attributes"]["customerPrice"]) == 0)
    else:
        client.call("GET", f"/v1/apps/{APP_ID}/appPricePoints?filter[territory]={BASE_TERRITORY}",
                    note="find the point with customerPrice 0")
        free = "<free price point id>"
    client.call("POST", "/v1/appPriceSchedules", {"data": {
        "type": "appPriceSchedules", "relationships": {
            "app": ref("apps", APP_ID), "baseTerritory": ref("territories", BASE_TERRITORY),
            "manualPrices": {"data": [{"type": "appPrices", "id": "${price1}"}]}}},
        "included": [{"type": "appPrices", "id": "${price1}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": ref("appPricePoints", free)}}]}, "8 price free")
    return sold


def eula(client, sold):
    # 9. Custom licence agreement for every territory the app is sold in.
    text = eula_text()
    if text is None:
        if client.live:
            sys.exit("eula.md still has OWNER TO PROVIDE placeholders")
        text = "<eula.md text, once its placeholders are filled>"
    client.call("POST", "/v1/endUserLicenseAgreements", {"data": {
        "type": "endUserLicenseAgreements", "attributes": {"agreementText": text},
        "relationships": {"app": ref("apps", APP_ID), "territories": {
            "data": [{"type": "territories", "id": t} for t in sold]}}}},
        "9 licence agreement. If one exists, PATCH /v1/endUserLicenseAgreements/{id}")


def screenshots(client, version_loc, folder):
    # 10. Apple TV screenshots, in order.
    files = [Path(folder) / f"{name}.png" for name in SCREENSHOT_ORDER] if folder else []
    missing = [f.name for f in files if not f.exists()]
    if not folder or missing:
        message = f"screenshots missing: {missing or 'no folder given'}"
        if client.live:
            sys.exit(message)
        print("\n# " + message)
    sets = client.get_all(f"/v1/appStoreVersionLocalizations/{version_loc['id']}/appScreenshotSets")
    existing = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_APPLE_TV"), None)
    if existing and client.live:
        sys.exit("an APP_APPLE_TV screenshot set already exists; delete its screenshots in the web UI or "
                 "DELETE /v1/appScreenshots/{id} first, so the order is ours")
    made = client.call("POST", "/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_APPLE_TV"},
        "relationships": {"appStoreVersionLocalization": ref("appStoreVersionLocalizations", version_loc["id"])}}},
        "10 screenshot set")["data"]
    ids = []
    for file in files or [Path(f"{n}.png") for n in SCREENSHOT_ORDER]:
        size = file.stat().st_size if file.exists() else 0
        reserved = client.call("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": file.name, "fileSize": size},
            "relationships": {"appScreenshotSet": ref("appScreenshotSets", made["id"])}}},
            f"10 reserve {file.name}")["data"]
        if client.live:
            data = file.read_bytes()
            for op in reserved["attributes"]["uploadOperations"]:
                part = urllib.request.Request(op["url"], method=op["method"],
                                              data=data[op["offset"]:op["offset"] + op["length"]])
                for header in op.get("requestHeaders", []):
                    part.add_header(header["name"], header["value"])
                urllib.request.urlopen(part, timeout=120).read()
            checksum = hashlib.md5(data).hexdigest()
        else:
            print("PUT <each uploadOperations url>    # the file's bytes, in the parts Apple gives")
            checksum = "<md5 of the file>"
        client.call("PATCH", f"/v1/appScreenshots/{reserved['id']}", {"data": {
            "type": "appScreenshots", "id": reserved["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}}, f"10 commit {file.name}")
        ids.append(reserved["id"])
    client.call("PATCH", f"/v1/appScreenshotSets/{made['id']}/relationships/appScreenshots",
                {"data": [{"type": "appScreenshots", "id": i} for i in ids]}, "10 order")


def encryption(client, build_id):
    # 11. Export compliance for an uploaded build: standard, third-party (OpenSSL), not in France.
    declaration = client.call("POST", "/v1/appEncryptionDeclarations", {"data": {
        "type": "appEncryptionDeclarations", "attributes": {
            "appDescription": ENCRYPTION_DESCRIPTION, "containsProprietaryCryptography": False,
            "containsThirdPartyCryptography": True, "availableOnFrenchStore": False},
        "relationships": {"app": ref("apps", APP_ID)}}}, "11 encryption declaration")["data"]
    client.call("POST", f"/v1/appEncryptionDeclarations/{declaration['id']}/relationships/builds",
                {"data": [{"type": "builds", "id": build_id}]}, "11 attach to build")
    client.call("PATCH", f"/v1/builds/{build_id}", {"data": {
        "type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": True}}}, "11 build flag")
    # 12. Choose that build for version 1.0.
    version = one(client, f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]={PLATFORM}"
                          f"&filter[versionString]={VERSION}", f"appStoreVersion {VERSION}")
    client.call("PATCH", f"/v1/appStoreVersions/{version['id']}", {"data": {
        "type": "appStoreVersions", "id": version["id"],
        "relationships": {"build": ref("builds", build_id)}}}, "12 build for 1.0")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["plan", "apply", "encryption"])
    parser.add_argument("--yes", action="store_true", help="needed to send anything")
    parser.add_argument("--build", help="build id, for encryption")
    parser.add_argument("--screenshots", default=os.environ.get("FINESSE_SCREENSHOTS"))
    args = parser.parse_args()
    live = args.mode != "plan"
    if live and not args.yes:
        sys.exit("refusing to change App Store Connect without --yes")
    client = Client(live)
    if args.mode == "encryption":
        encryption(client, args.build or sys.exit("--build is required"))
        return
    _, version, version_loc = listing(client)
    review_details(client, version)
    sold = availability_and_price(client)
    eula(client, sold)
    screenshots(client, version_loc, args.screenshots)
    if not live:
        encryption(client, "<build id, after upload>")
        print(f"\n# {client.fake} requests planned. App Privacy is a manual step, see asc-api.md.")


if __name__ == "__main__":
    main()
