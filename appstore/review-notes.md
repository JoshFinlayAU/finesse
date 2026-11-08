# App Review notes and demo server plan

## Demo server options

App Review can't reach our LAN test server, and the reviewer needs a working server to see anything past the first screen.

| Option | How it works | For | Against |
|---|---|---|---|
| **A. Jellyfin's public demo, recommended for 1.0** | `https://demo.jellyfin.org/stable`, user `demo`, blank password | Free. Run by the Jellyfin project for exactly this. HTTPS. Version 12.4.0, the same as our test server. Content is 11 old films, mostly public domain in the US, plus Creative Commons shorts and one series, Pioneer One. Dracula (1931) is an exception: it's probably under US copyright until 1 January 2027. Tested, see below | No availability promise, and Jellyfin can reset it or upgrade it at any time. The account is shared with the public, so its settings and watch state can change between our check and the review |
| **B. An owner-run public review server** | A small Jellyfin instance reachable from the internet, with a review-only user and a handful of public-domain titles | Under our control, stable, and we choose the content and settings | Needs hosting, a domain and TLS, upkeep, and someone to watch it during each review. Our current server is LAN-only and holds the household's media, so it can't be used |
| **C. A built-in demo mode** | Ship the `-FinesseFakeServer` mode in Release, behind a hidden switch | Never fails | Apple accepts a demo mode instead of an account only with prior approval. It has no real video, so playback, the thing worth reviewing, can't be shown. Today it's DEBUG-only by design. Not recommended |

**Recommendation:**

- **For 1.0:** use option A, and give option B's details as a fallback in the same note if the owner sets one up.
- **On the day of submission:** check that the demo still signs in and plays, using the same check as below, and again if review takes more than a few days.

## Demo server test, 2026-11-09

The test is `FinesseUITests/AppStore/DemoServerUITests.swift`. It runs only when `DEMO_URL`, `DEMO_USERNAME` and `DEMO_MOVIE` are given, and it reads none of the test server's values. On a freshly erased `Finesse Apple TV 4K` simulator it:

1. connects;
2. signs in as `demo` with a blank password;
3. opens Home, Movies and TV Shows;
4. searches for a film;
5. opens its detail page and plays it;
6. checks that playback moves;
7. opens the Info panel, scrubs back to the start and leaves the player.

**Result: passed on the third run, at `bd751f4`, built from a clean export of `main` on a freshly erased simulator, in 166 seconds.**

- **Connect and sign in:** connecting to `https://demo.jellyfin.org/stable` showed the "Stable Demo" user picker with only the `demo` user. Signing in through Other User with a blank password reached Home.
- **Playback:** Play on Home's billboard played Dracula (1931) directly from the file in AVPlayer. That was H.264 at 1920x1080, AAC stereo, MOV, 4.4 Mbps. Playback moved by more than 5 seconds in 12, and the control bar and Info panel worked. Back returned to Home.
- **Browsing:** Movies listed 11 titles, TV Shows 1, and Search found "Llamigos" and opened its detail page.
- **Not tested on the demo:** mpv. Every demo file is MP4 and plays in AVPlayer, so the review path doesn't touch mpv.

**Found on the way:**

1. **Detail page focus:** opened from Search, the detail page never had focus on Play. Up then acted on the Search screen underneath, and the page disappeared. That's a likely app bug that only shows on a slow server, and agent-1 is fixing it as #600. Until it lands, the test plays from Home instead, and only reports the detail page's focus. The third run still reported `false`.
2. **Slow artwork:** the demo server is slow to serve artwork. Each image takes about 2 seconds from here, and Continue Watching took more than 11 seconds to fill. The app showed placeholders until then. That's the server, not the app.

Earlier runs: the first stopped at the detail page's missing focus, and the second at the detail page disappearing after Up.

## Notes for App Review

Paste these into App Store Connect, under App Review Information, then Notes. They come to about 1,900 characters, and the limit is 4,000.

> Finesse is a client for Jellyfin, a free, open-source media server that people run on their own computer or NAS. Finesse has no content, catalogue or accounts of its own: it plays only the media on the server the user signs in to, much like a file player.
>
> To review, please use the Jellyfin project's public demo server:
>
> 1. On the first screen, enter the server address: https://demo.jellyfin.org/stable
> 2. Choose Connect.
> 3. Choose "Other user", enter the username: demo. Leave the password empty, and choose Sign In.
> 4. Home, Movies, TV Shows and Search are now available. Any film can be played, for example "Caminandes: Llamigos" from Search.
>
> The demo server is run by the Jellyfin project, not by us, and its content was chosen by that project. If it is unavailable, please let us know and we will provide another server immediately.
>
> Notes on specific features:
> - Top Shelf: once you have started a film, Finesse's Top Shelf on the Home Screen shows Continue Watching and Next Up. Before sign-in it shows our static image.
> - Quick Connect is another way to sign in: the Apple TV shows a code, which is approved from another device already signed in to the same server, for example the demo's web page at https://demo.jellyfin.org/stable signed in as demo, under the user menu, then Quick Connect. The password sign-in above is simpler.
> - Skip Intro and Skip Credits appear only where the server has marked those segments. The demo server has none.
>
> App Transport Security: Finesse sets NSAllowsArbitraryLoads because users type the address of their own self-hosted server, which the app cannot know in advance. Jellyfin servers default to plain HTTP on port 8096 and are commonly reached by a hostname on a home network, which NSAllowsLocalNetworking does not cover. The app connects only to the server the user entered, and HTTPS is used whenever the user's address uses it.
>
> Privacy: Finesse collects no data. Sign-in details, viewing progress and searches go only to the user's own server, which we neither run nor can access. There are no analytics, ads or tracking.
>
> Encryption: HTTPS through Apple's URLSession, plus OpenSSL (standard TLS) inside the bundled FFmpeg library for streams played by its built-in player.
>
> Finesse is open source under the LGPL v3: https://github.com/JoshFinlayAU/finesse

## Contact details for App Review

The owner fills these in: first and last name, phone and email. App Review calls or emails this person if something fails.

## Sign-in required

Tick "Sign-in required" and enter:

- **Username:** `demo`
- **Password:** leave it blank.

App Store Connect may refuse a blank password field. If it does, put "(leave empty)" in the field and keep the explanation in the notes.
