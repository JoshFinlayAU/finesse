# Finesse privacy policy

Last updated: 9 November 2026

Finesse is an Apple TV app for watching media on a Jellyfin server. It is published by Athena Networks, which is responsible for this policy. This policy explains what happens to your information when you use the app.

## The short version

Finesse collects nothing. We receive no data from the app: no accounts, analytics, advertising, crash reporting services or tracking. The app talks only to the Jellyfin server you choose.

## What the app sends to your server

To sign you in and play your media, Finesse sends information to the Jellyfin server whose address you enter, and to no one else:

- your username and password when you sign in. The password is sent once to get a sign-in token, and is never stored.
- a sign-in token with each request, which identifies your session to your server.
- your Apple TV's device name and a random identifier created by the app, so your server can list the device under its sessions.
- what you watch and how far through you are, so your server can offer Continue Watching and Next Up and resume playback.
- your searches, and choices such as favourites, watched status and track selections.

That server is run by you, or by whoever gave you access to it, not by us. What it does with this information is up to that server and the person who runs it. Jellyfin's own documentation describes the server.

## What is stored on your Apple TV

- **Sign-in tokens:** server addresses and sign-in tokens for the users you have signed in are kept in the Apple TV's keychain, so you stay signed in. They are shared with Finesse's Top Shelf extension, so it can show your Continue Watching on the Home Screen.
- **Disposable caches:** artwork and some settings, such as your preferred sort order, are stored by the app. tvOS can remove these at any time.
- **Removing it:** signing out removes that user's token from the Apple TV and ends the session on your server. Deleting the app removes its caches and settings. The keychain can keep items after an app is deleted, so sign out of each user first to remove their tokens as well.

## Children

Finesse does not knowingly collect information from anyone, including children. What a child can watch depends on the server and the parental controls its operator sets for each user.

## Changes

If this policy changes, the new version will be published at this address with a new date. The history of every change is public in this repository.

## Contact

Athena Networks

- Email: support@athenanetworks.com.au
- Phone: 1300 409 252 (from within Australia)
- Post: Parcel Locker 10303 80643, 139 Brisbane Road, Booval QLD 4304, Australia

You can also open an issue at https://github.com/JoshFinlayAU/finesse/issues.
