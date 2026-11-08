# App Store metadata draft

For the tvOS listing in English (Australia). The character limits are App Store Connect's. Nothing here has been entered into App Store Connect.

## Name

Finesse (7 of 30). This matches the existing record.

## Subtitle

Up to 30 characters. The first option is recommended:

1. "For your Jellyfin server" (24)
2. "A Jellyfin client for Apple TV" (30)
3. "Your own media, beautifully" (27)

Apple allows another product's name in the subtitle when it describes compatibility. "Jellyfin" is the most useful search term we have. Jellyfin is a registered project name, so we use it only to say what the app works with. The app doesn't use Jellyfin's logo.

## Promotional text

Up to 170 characters. It can be changed without a new version.

> Watch the films and shows on your own Jellyfin server with an Apple TV app built for the big screen: fast browsing, smooth playback and support for almost any file.

(163)

## Description

Up to 4,000 characters.

> Finesse is an Apple TV app for Jellyfin, the free media server you run yourself. Sign in to your server and your films and TV shows are ready to watch, with an interface designed for the Siri Remote and the living room.
>
> YOUR LIBRARY, ORGANISED
> • Home shows Continue Watching, Next Up and Recently Added, so what you were watching is always one click away.
> • Browse Movies and TV Shows with sorting and filters by genre, year, rating, tags and more.
> • Detail pages for films, shows, seasons and episodes, with cast and related titles.
> • Search across your whole library.
> • Top Shelf puts what you're watching on the Apple TV Home Screen.
>
> PLAYBACK THAT JUST WORKS
> • Plays most files directly, including MKV, with AV1, HEVC and many audio formats, using Apple's player where it can and a built-in engine where it can't.
> • Choose audio and subtitle tracks, including styled ASS and image-based PGS subtitles.
> • Skip Intro and Skip Credits where your server has marked them.
> • The next episode plays automatically when the current one ends.
> • Resume where you left off, on any device that uses your server.
>
> MADE FOR THE WHOLE HOUSEHOLD
> • Switch between users on your server in a couple of clicks.
> • Sign in with a password or with Quick Connect from another device.
>
> PRIVATE BY DESIGN
> Finesse talks only to the server you enter. It has no accounts, no ads, no analytics and no tracking, and it collects no data.
>
> OPEN SOURCE
> Finesse is open source under the GNU LGPL version 3. The code is on GitHub.
>
> Finesse requires a Jellyfin server, version 10.10 or later, that you run or have access to. It does not include any films or shows. Jellyfin is a trademark of its respective owners, and Finesse is not affiliated with or endorsed by the Jellyfin project.

**Check before use:**

- **Server version:** "10.10 or later" is a placeholder. We've only tested against 12.4.0, on our server and the public demo, so the owner should pick a version we can stand behind. "12.4 or later" is the safe choice.
- **Formats:** check each format claim against the routing in `PlaybackRouter`. AV1 is decoded by dav1d, and HEVC needs hardware or mpv.

## Keywords

Up to 100 characters, separated by commas without spaces. Apple already indexes the name and subtitle, so don't repeat them:

`jellyfin,media server,player,mkv,movies,tv shows,home theater,streaming,subtitles,plex,emby,library`

That is 96 characters.

Using a competitor's name, such as "plex" or "emby", in keywords risks rejection under guideline 2.3.7. Without them the list is:

`jellyfin,media server,video player,mkv,movies,tv shows,home theater,streaming,subtitles,hevc,library`

That is 99 characters, and it's the recommended version.

## Category

- **Primary:** Entertainment.
- **Secondary:** Photo & Video is optional and fits. tvOS supports a secondary category.

## URLs

These are proposals, and the owner decides.

| Field | Required | Proposal |
|---|---|---|
| Support URL | Yes | `https://github.com/JoshFinlayAU/finesse/issues`. Apple wants a way to contact the developer, so the page should also give an email address. A `SUPPORT.md` in the repo, or a GitHub Pages page, can carry both. |
| Marketing URL | No | `https://joshfinlayau.github.io/finesse/`, a one-page GitHub Pages site, or leave it blank for 1.0. |
| Privacy Policy URL | Yes, for every app | `https://github.com/JoshFinlayAU/finesse/blob/main/PRIVACY.md`, or the same text on the Pages site. See `privacy-policy.md`. |

## Copyright

The proposal is "© 2026 Josh Finlay". If the app is published under Athena Networks as seller, use that name instead. It should match the seller name on the developer account, which isn't recorded here.

## Version and what's new

- **Version:** 1.0, which matches App Store Connect. The app and the Top Shelf extension take it from build settings since `b8f56d3` (agent-1, #562).
- **What's new:** not shown for a first release.

## Price and availability

These are owner decisions:

- **Price:** free is recommended. It's open source, and in-app purchases aren't in scope.
- **Regions:** France affects export compliance. See `export-compliance.md`.
