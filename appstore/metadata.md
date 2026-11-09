# Listing text

The App Store listing for Finesse on Apple TV, in English (Australia). `asc_apply.py` reads each block below, so edit the text here and nowhere else. The limits are App Store Connect's.

The app's name is Finesse.

## Subtitle

Up to 30 characters.

<!-- asc:subtitle -->
```
For your Jellyfin server
```

## Promotional text

Up to 170 characters. It can be changed at any time without submitting a new version.

<!-- asc:promotionalText -->
```
Watch the films and shows on your own Jellyfin server with an Apple TV app built for the big screen: fast browsing, smooth playback and support for almost any file.
```

## Description

Up to 4,000 characters, in plain text.

<!-- asc:description -->
```
Finesse is an Apple TV app for Jellyfin, the free media server you run yourself. Sign in to your server and your films and TV shows are ready to watch, with an interface designed for the Siri Remote and the living room.

YOUR LIBRARY, ORGANISED
- Home shows Continue Watching, Next Up and Recently Added, so what you were watching is always one click away.
- Browse Movies and TV Shows with sorting and filters by genre, year, rating, tags and more.
- Detail pages for films, shows, seasons and episodes, with cast and related titles.
- Search across your whole library.
- Top Shelf puts what you're watching on the Apple TV Home Screen.

PLAYBACK THAT JUST WORKS
- Plays most files directly, including MKV, with AV1, HEVC and many audio formats, using Apple's player where it can and a built-in engine where it can't.
- Choose audio and subtitle tracks, including styled ASS and image-based PGS subtitles.
- Skip Intro and Skip Credits where your server has marked them.
- The next episode plays automatically when the current one ends.
- Resume where you left off, on any device that uses your server.

MADE FOR THE WHOLE HOUSEHOLD
- Switch between users on your server in a couple of clicks.
- Sign in with a password or with Quick Connect from another device.

PRIVATE BY DESIGN
Finesse talks only to the server you enter. It has no accounts, no ads, no analytics and no tracking, and it collects no data.

OPEN SOURCE
Finesse is open source under the GNU LGPL version 3. The code is on GitHub.

Finesse requires a Jellyfin server, version 12.4 or later, that you run or have access to. It does not include any films or shows. Jellyfin is a trademark of its respective owners, and Finesse is not affiliated with or endorsed by the Jellyfin project.
```

## Keywords

Up to 100 characters, separated by commas. The name and subtitle are already indexed, so they aren't repeated here.

<!-- asc:keywords -->
```
jellyfin,media server,video player,mkv,movies,tv shows,home theater,streaming,subtitles,hevc,library
```

## Links

Finesse has no marketing site, so the marketing URL is left empty. Support goes through GitHub Issues, and `SUPPORT.md` in the repository gives the email and phone number as well.

<!-- asc:supportUrl -->
```
https://github.com/JoshFinlayAU/finesse/issues
```

<!-- asc:privacyPolicyUrl -->
```
https://github.com/JoshFinlayAU/finesse/blob/main/PRIVACY.md
```

## Other details

The primary category is Photo & Video and the secondary is Entertainment, chosen by the owner when they created the record in App Store Connect. `asc_apply.py` checks them and doesn't change them. Finesse is free and sold everywhere except France, where the encryption rules would need a separate declaration (see `export-compliance.md`). New App Store territories aren't added automatically.

The copyright line is entered without the copyright sign, which the store adds itself:

<!-- asc:copyright -->
```
2026 Athena Networks
```
