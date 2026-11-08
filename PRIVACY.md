# Finesse privacy policy

Last updated: 9 November 2026

Finesse is an Apple TV app for watching media on a Jellyfin server. It is published by Athena Networks, which is responsible for this policy.

Finesse collects nothing. We receive no data from the app, and it has no accounts, analytics, advertising, crash reporting services or tracking. The app talks only to the Jellyfin server you choose.

## What the app sends to your server

To sign you in and play your media, Finesse sends information to the Jellyfin server whose address you enter, and to no one else:

- your username and password when you sign in. The password is sent once to get a sign-in token, and is never stored.
- a sign-in token with each request, which identifies your session to your server.
- your Apple TV's device name and a random identifier created by the app, so your server can list the device under its sessions.
- what you watch and how far through you are, so your server can offer Continue Watching and Next Up and resume playback.
- your searches, and choices such as favourites, watched status and track selections.

That server is run by you, or by whoever gave you access to it, not by us. What it does with this information is up to that server and the person who runs it.

## What is kept on your Apple TV

The address of your server and a sign-in token for each user you've signed in are kept in the Apple TV's keychain, so you stay signed in. Finesse's Top Shelf extension reads them too, so it can show what you're watching on the Home Screen.

The app also keeps artwork and a few settings, such as your preferred sort order. tvOS may clear these at any time.

Signing out removes that user's token from the Apple TV and ends the session on your server. Deleting the app removes its artwork and settings, but the keychain can keep items after an app is deleted, so sign out of each user first if you want their tokens gone too.

## Children

Finesse does not knowingly collect information from anyone, including children. What a child can watch depends on the server and the parental controls its operator sets for each user.

## Changes

If this policy changes, the new version will be published here with a new date. Every change is visible in this repository's history.

## Contact

Athena Networks, Parcel Locker 10303 80643, 139 Brisbane Road, Booval QLD 4304, Australia.

Email support@athenanetworks.com.au, or call 1300 409 252 from within Australia. You can also open an issue at https://github.com/JoshFinlayAU/finesse/issues.
