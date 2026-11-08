# Export compliance

## What encryption the app contains

| Where | What | Notes |
|---|---|---|
| The app and the Top Shelf extension, through `URLSession` | TLS for HTTPS, provided by tvOS | This is the encryption within Apple's operating system |
| The keychain | Tokens kept with Apple's keychain | This also belongs to Apple's operating system |
| `OpenSSL.framework`, OpenSSL 3.5.9, used by `Libavformat` | TLS 1.2 and 1.3 for HTTPS streams that mpv plays | Standard algorithms, public source and unmodified. It ships in the app bundle, so it isn't Apple's operating system. FFmpeg was built with OpenSSL by the owner's decision, for TLS 1.3. See `tvos-deps/README.md`, "HTTPS" |

No proprietary or non-standard algorithms are used. Encryption is used only to protect the connection to the user's own server, not to encrypt user data or as a feature in its own right.

## App Store Connect answers

App Store Connect asks these on the first build upload, unless `Info.plist` already answers them.

1. **Does your app use encryption?**
   - **Answer:** Yes. HTTPS counts, whoever provides it.
2. **Does it qualify for any of the exemptions?**
   - **Answer:** No.
   - **Why:** the exemptions cover apps that use only encryption within Apple's operating system, or encryption limited to authentication or copy protection. Finesse also bundles OpenSSL.
3. **What type of encryption algorithms does the app implement?**
   - **Answer:** "Standard encryption algorithms instead of, or in addition to, using or accessing the encryption within Apple's operating system".
4. **Is your app going to be available on the App Store in France?** This is an owner decision.
   - **Yes:** Apple asks for the French encryption declaration, which is a filing with France's ANSSI. Upload it in App Store Connect before the build can be released there. Expect several weeks.
   - **No:** France is removed from availability, and no documents are needed.

Under US export rules, an app like this is mass-market software with standard encryption, classified 5D992.c. Since BIS's 2021 rule change, mass-market end items under licence exception ENC 740.17(b)(1) no longer need the annual self-classification report. Apple still asks the questions above, and the French declaration under question 4 is the only document in play.

**Not legal advice:** this is drawn from Apple's help pages and the published rules. The owner may want it checked by someone qualified, especially the French filing.

## `ITSAppUsesNonExemptEncryption` in `Info.plist`

**Don't set it to `false`.**

- **Why not:** `false` tells Apple the app uses no encryption beyond the exempt kinds. That's true only if the app limited itself to tvOS's own TLS, which it doesn't, because of OpenSSL in Libavformat. Setting `false` would answer question 2 wrongly on every upload.

**The choices are:**

1. **Leave the key out for the first submission.** App Store Connect asks the questions in the web UI for the first build, and the answers are reviewed with it. This is recommended for 1.0.
2. **Set `ITSAppUsesNonExemptEncryption` to `true`** after the first review. If Apple issues a compliance code for approved documents, which happens only when documents are required, add `ITSEncryptionExportComplianceCode` too. That stops the questions coming back with every TestFlight upload.

**Who does what:** agent-1 makes any `Info.plist` change after the merge. For 1.0 none is needed under option 1. Agent-3 should expect the export compliance question on the first upload and leave it for the owner, because it's an App Store Connect answer.

## How `false` could become right

FFmpeg could be built without OpenSSL, getting TLS from Apple instead.

- **Why it doesn't work today:** FFmpeg's Apple TLS backend is SecureTransport, which is deprecated and stops at TLS 1.2. A TLS 1.3-only host failed with it in testing on 2026-11-06.
- **What it would take:** a build without OpenSSL that loses TLS 1.3 in mpv. The other route is mpv using a Network.framework stream, which would need new code. Neither is recommended for 1.0.

## Sources

- Apple, App Store Connect Help, "Export compliance documentation for encryption", which covers the French declaration for algorithms not provided by Apple's operating system: https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption
- Apple, "Overview of export compliance": https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- Developer forum notes on removing France to avoid the declaration: https://developer.apple.com/forums/thread/725047
