# App Store metadata

For the tvOS listing in English (Australia). Status as of 2026-11-09:

- **FINAL:** approved by the owner, or set by the manager's defaults in #623.
- **OPEN:** still needs the owner.

Each final text sits in a block marked `asc:<field>`, which `asc_apply.py` reads, so there is one copy of every string. The limits are App Store Connect's.

## Name: FINAL

Finesse (7 of 30). This matches the existing record, and the script doesn't change it.

## Subtitle: FINAL

Option 1 of the three drafted, 24 of 30 characters.

<!-- asc:subtitle -->
```
For your Jellyfin server
```

"Jellyfin" only says what the app works with. The app doesn't use Jellyfin's logo, and the description says it isn't affiliated.

## Promotional text: FINAL

164 of 170 characters. It can be changed later without a new version.

<!-- asc:promotionalText -->
```
Watch the films and shows on your own Jellyfin server with an Apple TV app built for the big screen: fast browsing, smooth playback and support for almost any file.
```

## Description: FINAL

1,752 of 4,000 characters. App Store descriptions are plain text, so lists use hyphens.

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

**Server version:** 12.4.0 is the lowest version tested. Both our test server and Jellyfin's stable demo ran 12.4.0 on 2026-11-09, and the demo's unstable instance ran 13.0.0, which wasn't tested with the app. Older servers may work, but nothing has been checked against them.

**Formats:** the claims match `PlaybackCapabilities`. AVPlayer takes H.264 and HEVC. mpv adds AV1 through dav1d, VP8 and VP9, MPEG-2, VC-1 and others. Real-device checks for mpv, such as hardware decode, are still on the list in `memory/player-signoff.md`, so play one file of each format on the Apple TV before release.

## Keywords: FINAL

The recommended list without competitor names, exactly 100 of 100 characters.

<!-- asc:keywords -->
```
jellyfin,media server,video player,mkv,movies,tv shows,home theater,streaming,subtitles,hevc,library
```

## Category: FINAL

- **Primary:** Entertainment (`ENTERTAINMENT`).
- **Secondary:** none. Photo & Video would fit, but nobody chose it, so it's left empty.

## URLs: FINAL, except the email

| Field | Value |
|---|---|
| Support URL | `https://github.com/JoshFinlayAU/finesse/issues` |
| Marketing URL | None for 1.0 |
| Privacy Policy URL | `https://github.com/JoshFinlayAU/finesse/blob/main/PRIVACY.md` |

<!-- asc:supportUrl -->
```
https://github.com/JoshFinlayAU/finesse/issues
```

<!-- asc:privacyPolicyUrl -->
```
https://github.com/JoshFinlayAU/finesse/blob/main/PRIVACY.md
```

**Before use:**

- **Push to GitHub first:** both URLs need the repo on GitHub to be current. The issues page needs Issues enabled. `PRIVACY.md` must be pushed to `main`, which needs the owner's go-ahead.
- **Email:** OPEN. The owner gave no support email. GitHub Issues is the contact for now, but the licence agreement needs an email, a phone number and an address under Apple's rules. See `eula.md`.

## Copyright: FINAL

The owner chose "2026 Athena Networks" with the copyright sign. App Store Connect's field takes the year and holder, as in Apple's example "2008 Acme Inc.", and the store adds the copyright sign itself. So the field gets:

<!-- asc:copyright -->
```
2026 Athena Networks
```

Check the product page preview after saving. If the copyright sign is missing, add it to the field.

## Version: FINAL

1.0, which matches App Store Connect. The app and the Top Shelf extension take it from build settings since `b8f56d3`. "What's New" isn't shown for a first release.

## Price and availability: FINAL

- **Price:** free.
- **Availability:** every territory except France, so no French encryption declaration is needed. See `export-compliance.md`.
- **New territories:** off, so France or any new territory is never added without someone deciding.
