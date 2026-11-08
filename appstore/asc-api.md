# Entering the listing through the App Store Connect API

**Status:** drafted and checked offline on 2026-11-09. **Not run.** It changes App Store Connect, so it needs the owner's word first.

`asc_apply.py` sends all of it in one go. It reads every text from the `asc:` blocks in `metadata.md`, `review-notes.md` and `eula.md`, so it can't drift from what the owner approved.

- **`plan`, the default:** prints every request offline and touches nothing.
- **`apply --yes`:** sends them.

The endpoints and fields were checked against Apple's OpenAPI specification for the App Store Connect API, version 4.6, downloaded on 2026-11-09.

## Before running

1. **The owner's go-ahead,** for App Store Connect changes in general.
2. **The open items filled in:**
   - **Licence agreement:** the contact lines and governing-law state in `eula.md`. The script refuses to send the agreement while "OWNER TO" remains.
   - **Review contact:** four environment variables, `ASC_REVIEW_FIRST_NAME`, `ASC_REVIEW_LAST_NAME`, `ASC_REVIEW_PHONE` and `ASC_REVIEW_EMAIL`.
3. **`PRIVACY.md` pushed to `main` on GitHub,** so the privacy URL works when review opens it. Pushing needs the owner's go-ahead too.
4. **The final screenshots in one folder,** named as in `screenshots.md`, passed with `--screenshots <folder>`. The script refuses to run if any is missing.
5. **An API key with the App Manager role:**
   - **IDs:** `ASC_KEY_ID` and `ASC_ISSUER_ID` come from the environment, never the repo.
   - **The `.p8`:** found at `ASC_KEY_PATH`, or by default at `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`, the same place agent-3's `scripts/app-store-archive.sh` uses.
   - **Python:** needs the `cryptography` package.

Then run, from the spoke root, wherever the key is:

```sh
python3 appstore/asc_apply.py plan --screenshots <folder>        # read it through first
python3 appstore/asc_apply.py apply --yes --screenshots <folder>
```

After agent-3 uploads the build and it finishes processing:

```sh
python3 appstore/asc_apply.py encryption --build <build id> --yes
```

## What it sends

| Step | Request | What |
|---|---|---|
| 1 | `PATCH /v1/appInfoLocalizations/{id}` (en-AU) | Subtitle, privacy policy URL |
| 2 | `PATCH /v1/appInfos/{id}` | Primary category `ENTERTAINMENT`, no secondary |
| 3 | `PATCH /v1/ageRatingDeclarations/{id}` | Every content answer `NONE` and every capability `false`, giving 4+, with no override |
| 4 | `PATCH /v1/appStoreVersions/{id}` (1.0) | Copyright `2026 Athena Networks`, manual release after approval |
| 5 | `PATCH /v1/appStoreVersionLocalizations/{id}` (en-AU) | Description, keywords, promotional text, support URL. No marketing URL |
| 6 | `POST /v1/appStoreReviewDetails`, or `PATCH` if one exists | Contact, demo account `demo` with a blank password, review notes |
| 7 | `POST /v2/appAvailabilities` | Every territory except `FRA`, and new territories off |
| 8 | `POST /v1/appPriceSchedules` | Free, with Australia as the base territory |
| 9 | `POST /v1/endUserLicenseAgreements` | The custom licence agreement, for every territory sold in |
| 10 | `POST /v1/appScreenshotSets`, then `POST /v1/appScreenshots`, the upload parts and `PATCH` for each file | 8 Apple TV screenshots (`APP_APPLE_TV`), uploaded and put in order |
| 11 | `POST /v1/appEncryptionDeclarations`, attach to the build, `PATCH /v1/builds/{id}` | Standard third-party encryption, not proprietary, not in France, and `usesNonExemptEncryption` true |
| 12 | `PATCH /v1/appStoreVersions/{id}` | The uploaded build chosen for 1.0 |

The script looks up the IDs that only exist in App Store Connect itself, such as the app info and the 1.0 version, with GET requests first. `plan` shows these as `<...>` placeholders.

## Manual steps, which have no API

- **App Privacy:** App Store Connect, then App Privacy. Choose "No, we do not collect data from this app", save, then Publish. See `privacy-policy.md`.
- **Submit for review:** done by the owner in the web UI after checking the product page preview. The script never submits.

## Known edges

- **Step 7:** availability can be set only once with `POST`. If the record already has availability, the POST fails, and France has to be turned off with `PATCH /v1/territoryAvailabilities/{id}` instead.
- **Step 9:** the same applies to an existing licence agreement, which needs `PATCH /v1/endUserLicenseAgreements/{id}`.
- **Step 10:** the script stops if an Apple TV screenshot set already exists, so it never mixes old and new screenshots. Delete the old ones first.
- **Blank demo password:** App Store Connect may reject `demoAccountPassword` as empty. If so, send "(leave empty)", since the notes already say to leave it blank.
- **App Privacy has no API:** the API doesn't expose App Privacy answers, so publishing them is the one step that has to be done by hand before submission.
