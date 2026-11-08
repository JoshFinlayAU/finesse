# App Store listing

This folder holds what goes into App Store Connect for Finesse on Apple TV:

- `metadata.md` has the listing text and links.
- `review-notes.md` has the App Review information and how to check the demo server it relies on.
- `eula.md` is the licence agreement.
- `screenshots.md` lists the screenshots.
- `export-compliance.md` and `age-rating.md` hold the questionnaire answers.

The privacy policy is `PRIVACY.md` at the top of the repository. For App Privacy in App Store Connect the answer is "No, we do not collect data from this app", because Finesse only talks to the user's own server. That matches the app's privacy manifests.

## Entering it

`asc_apply.py` enters everything through the App Store Connect API in one run: the listing text, category, age rating, copyright, review information, availability, price, licence agreement and screenshots. It reads the text from the files here, so they stay the single source.

It needs an App Store Connect API key with the App Manager role and Python's `cryptography` package. The key's IDs come from the environment, and the `.p8` file is looked for in `~/.appstoreconnect/private_keys/` unless `ASC_KEY_PATH` says otherwise.

```sh
export ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id>
python3 appstore/asc_apply.py plan --screenshots <folder>         # prints every request, sends nothing
python3 appstore/asc_apply.py apply --yes --screenshots <folder>
```

Once a build has been uploaded and processed, attach it to version 1.0 along with its export compliance answers:

```sh
python3 appstore/asc_apply.py encryption --build <build id> --yes
```

Two things have no API and are done in the App Store Connect website: publishing the App Privacy answer, and submitting for review.

Availability and the licence agreement can only be created once through the API. On a second run those requests fail, and the existing records need editing instead. The script also stops if Apple TV screenshots are already uploaded, so old and new sets never mix.
