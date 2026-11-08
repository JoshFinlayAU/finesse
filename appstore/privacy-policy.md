# Privacy policy and App Privacy answers

## Policy, final

**Text:** the policy is `PRIVACY.md` at the repo root. It names Athena Networks as responsible, per the owner's 2026-11-09 decision.

**Contact:** GitHub Issues. The owner gave no email, so a marked comment in the file shows where one goes.

**Privacy Policy URL:** `https://github.com/JoshFinlayAU/finesse/blob/main/PRIVACY.md`. It works once `PRIVACY.md` is pushed to `main` on GitHub. Nothing has been pushed yet, and that needs the owner's go-ahead.

**Checked against the code at `9fd9b54`, and still true at `4acb45a`:**

- **Network:** the app and the extension contain no network hosts other than the server the user enters. The only hard-coded URLs are `.invalid` placeholders used by the fake-server mode.
- **Third-party SDKs:** none for analytics, crash reporting or advertising. The packages are the Jellyfin SDK, Get and Apple's SwiftNIO libraries.
- **Device name:** it comes from `UIDevice.current.name` and goes only to the user's server.
- **Passwords:** never stored. The URL cache is kept off disk, see `memory/shared-url-cache.md`. Tokens live in the keychain group shared with the Top Shelf extension.

## App Privacy answers, final

**Answer: "No, we do not collect data from this app"**, so the label reads "Data Not Collected".

**Why this matches Apple's definition:**

- Apple counts data as collected when it leaves the device in a way that lets the developer, or the developer's partners, access it for longer than the real-time request needs.
- Finesse sends data only to a server the user chooses and runs, or was given by its operator. Neither Athena Networks nor any partner can reach that server or its data.
- Crash reports that users choose to share through Apple aren't declared, because Apple collects them, not the developer.

**Consistent with the manifests:**

- `Finesse/Resources/PrivacyInfo.xcprivacy` and `FinesseTopShelf/PrivacyInfo.xcprivacy` declare no tracking, no tracking domains and no collected data types.
- Each framework manifest declares only required-reason APIs.
- If data were ever declared, the manifests would have to change too, or App Store Connect's privacy report would disagree with the label.

**How to enter it:**

- **Web UI only:** the App Store Connect API has no endpoint for App Privacy answers, so they go in through the web UI, under App Privacy, then Get Started. `asc-api.md` lists it as a manual step.
- **Publish:** after answering, the answers must be published.

**Risk, in `risks.md`:** a reviewer could read "sends the username, password and viewing history to a server" as collection. The review notes explain the difference in advance.
