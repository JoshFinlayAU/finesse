# Privacy policy and App Privacy answers

## Where to host it

App Store Connect needs a public Privacy Policy URL, and the policy has to be reachable without signing in.

**Recommended:** commit the policy below as `PRIVACY.md` at the repo root, and use `https://github.com/JoshFinlayAU/finesse/blob/main/PRIVACY.md` as the URL.

- It works as soon as the commit is on `main`, and the repo is already public.
- Its history shows every change.
- The same file can later feed a GitHub Pages site, if the owner wants a marketing URL, without changing the text.

Don't commit until the manager confirms the move to `main`. Agent-1 owns the repo root during #555, so this file should be added either by agent-1 or after #555 closes.

## Policy text

Proposed for `PRIVACY.md`:

> # Finesse privacy policy
>
> Last updated: [date of publishing]
>
> Finesse is an Apple TV app for watching media on a Jellyfin server. This policy explains what happens to your information when you use it.
>
> ## The short version
>
> Finesse collects nothing. The developer receives no data from the app: no accounts, analytics, advertising, crash reporting services or tracking. The app talks only to the Jellyfin server you choose.
>
> ## What the app sends to your server
>
> To sign you in and play your media, Finesse sends information to the Jellyfin server whose address you enter, and to no one else:
>
> - your username and password when you sign in. The password is sent once, to get a sign-in token, and is never stored;
> - a sign-in token with each request, which identifies your session to your server;
> - your Apple TV's device name and a random identifier created by the app, so your server can list the device under its sessions;
> - what you watch, and how far through you are, so your server can offer Continue Watching and Next Up and resume playback;
> - your searches, and your choices such as favourites, watched status and track selections.
>
> That server is run by you or by whoever gave you access to it, not by the developer of Finesse. What it does with this information is governed by that server and its operator. Jellyfin's own documentation describes the server.
>
> ## What is stored on your Apple TV
>
> - **Sign-in tokens:** server addresses and tokens for the users you have signed in are kept in the Apple TV's keychain, so you stay signed in. They are shared with Finesse's Top Shelf extension, so it can show your Continue Watching on the Home Screen.
> - **Disposable caches:** artwork and some settings, such as your preferred sort order, are stored by the app. tvOS can remove these at any time.
> - **Removing it:** signing out removes that user's token from the Apple TV. Deleting the app removes its caches and settings. The keychain can keep items after an app is deleted, so sign out of each user first to remove their tokens as well. Signing out also ends the session on your server.
>
> ## Children
>
> Finesse does not knowingly collect information from anyone, including children. What a child can watch depends on the server and the parental controls its operator sets.
>
> ## Changes
>
> If this policy changes, the new version will be published at this address with a new date. The history of every change is public in the project's repository.
>
> ## Contact
>
> [support email address], or open an issue at https://github.com/JoshFinlayAU/finesse/issues.

**Checked against the code at `9fd9b54`:**

- **Hosts:** the app and the extension contain no network hosts other than the server the user enters. The only hard-coded URLs are `.invalid` placeholders, used in the fake-server mode only.
- **Third-party code:** no analytics, crash-reporting or advertising SDKs. Our packages are the Jellyfin SDK, Get and Apple's SwiftNIO libraries.
- **Device name:** it comes from `UIDevice.current.name` and goes to the user's server only.
- **Disk:** passwords aren't stored, and the URL cache is kept off disk under `memory/shared-url-cache.md`. Tokens are in the keychain group shared with the Top Shelf extension.

## App Privacy answers ("nutrition label")

The recommended answer is **"No, we do not collect data from this app"**, which makes the label "Data Not Collected".

**Why this is consistent with Apple's definition:**

- Apple counts data as collected when it leaves the device in a way that lets the developer, or the developer's third-party partners, access it for longer than the real-time request needs.
- Finesse sends data only to a server the user chooses and runs, or was given by its operator. Neither the developer nor any partner of the developer can reach that server or its data.
- Apple's guidance says data processed only on the device, or sent only to a server the user controls and the developer doesn't, isn't collection by the developer.
- Crash reports that users share with developers through Apple aren't declared, because Apple collects them, not the developer.

**Consistency with the privacy manifests:**

- `Finesse/Resources/PrivacyInfo.xcprivacy` declares no tracking, no tracking domains and an empty `NSPrivacyCollectedDataTypes`. "Data Not Collected" matches that.
- `FinesseTopShelf/PrivacyInfo.xcprivacy` is the same.
- Each framework manifest declares only required-reason APIs and no collected data.
- If the owner chose to declare data instead, the manifests would have to change too, or App Store Connect's privacy report would disagree with the label.

**The risk,** listed in `risks.md`: a reviewer may read "sends username, password and viewing history to a server" as collection. The review notes explain the difference in advance.
