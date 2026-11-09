# Finesse

Finesse is a Jellyfin client for Apple TV. It borrows its structure from the Plex app, with hub rows on Home, library grids you can sort and filter, and detail pages for movies, shows, seasons and episodes. It looks like tvOS 26, using Liquid Glass and system controls throughout.

It's an early, independent project. Version 1 concentrates on watching video well.

## What it does

- Connects to your Jellyfin server and signs in with a username and password or with Quick Connect
- Switches between users, keeping each one signed in
- Home with a billboard and rows for Continue Watching, Next Up, recently added movies and shows, favourites, and your libraries and genres
- Movie and TV libraries with sorting and a filter panel (watched state, resolution, genres, years, ratings, tags and more)
- Search across movies, shows and episodes
- Detail pages with cast, seasons, episodes and similar titles
- Playback that resumes where you left off and reports progress back to the server
- Audio and subtitle track selection, subtitle size, position and timing, and playback speed
- Skip Intro and Skip Credits buttons when the server has media segments
- Up Next, which plays the next episode automatically unless you cancel
- A Top Shelf for the Apple TV Home Screen, showing what you're in the middle of

Playback uses AVPlayer for anything Apple's player handles natively, and falls back to mpv with FFmpeg for the rest, such as MKV files, DTS and TrueHD audio, and PGS or ASS subtitles. If neither can play something directly, the server transcodes it.

Music, photos, Live TV and offline downloads aren't part of version 1.

## Requirements

- An Apple TV running tvOS 26 or later
- A Mac with Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A Jellyfin server. Finesse is tested against Jellyfin 12.4

## Building

The Xcode project isn't checked in. `project.yml` describes it, and XcodeGen generates it.

1. Build the playback frameworks. Finesse links 14 xcframeworks (mpv, the FFmpeg libraries, OpenSSL, libplacebo, MoltenVK and the libraries they need) that are built from source by the scripts in `tvos-deps/`. Follow "Building" in [tvos-deps/README.md](tvos-deps/README.md). The frameworks end up in `../FinesseDeps/dist`, next to this folder, which is where `project.yml` looks for them. Expect it to take about 10 minutes.

2. Generate the project and build for the simulator:

   ```sh
   xcodegen generate
   xcodebuild build -project Finesse.xcodeproj -scheme Finesse \
     -destination "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)"
   ```

   Use the name of any tvOS simulator you have installed. `xcrun simctl list devices available` lists them.

3. To run it on an Apple TV, open `Finesse.xcodeproj` in Xcode, set your own team and bundle identifier for the app and its Top Shelf extension, and run it on your device.

## Tests

There are six test plans.

- `Fast`, the default, runs every unit test and a short set of UI tests against a built-in fake server, so it needs no server. Use it for everyday changes.
- `Finesse` holds the unit tests alone. They run offline against recorded server responses.
- `Integration` talks to a real Jellyfin server as a test user.
- `UI` drives the app in the simulator with the Siri Remote API. Most of these run against the fake server and need nothing else. Some sign in to a real server and skip themselves when no server details are given.
- `Playback` holds the streaming and player tests, on both AVPlayer and mpv. Run it when you change playback.
- `Full` runs everything.

Debug builds in the simulator play no sound. Launch with `-FinesseAudio` to hear them.

Run the default `Fast` plan with:

```sh
xcodebuild test -project Finesse.xcodeproj -scheme Finesse \
  -destination "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)"
```

The integration tests and the server-backed UI tests read the server address and a test user's credentials from environment variables: `JELLYFIN_URL`, `JELLYFIN_USERNAME` and `JELLYFIN_PASSWORD`, plus `JELLYFIN_USERNAME_2` and `JELLYFIN_PASSWORD_2` for a second user in the user switching tests. `xcodebuild` passes variables to the tests when they're prefixed with `TEST_RUNNER_`, for example `TEST_RUNNER_JELLYFIN_URL`. Then add `-testPlan` and the plan's name to the command above.

Use an account made for testing. The tests change only that user's own state, such as watch progress and favourites, and put it back afterwards.

## Project layout

- `Finesse/App` starts the app and holds the signed-in state, users and navigation
- `Finesse/Features` has one folder per screen: sign-in, Home, libraries, detail pages, search, the player, settings and licences
- `Finesse/Jellyfin` is the client layer between the app and the server. Views never use the Jellyfin SDK directly
- `Finesse/Playback` holds the AVPlayer and mpv engines behind one interface, and the router that picks between them
- `Finesse/SharedUI` has the cards, rows and image loading the screens share
- `Finesse/TopShelf` and `FinesseTopShelf` provide the Top Shelf
- `Finesse/Resources/Licences` lists every component the app ships, with its licence text, for the in-app licences screen
- `FinesseTests`, `FinesseIntegrationTests` and `FinesseUITests` are the three kinds of tests
- `tvos-deps` builds the playback frameworks, with pinned versions, checksums and patches
- `branding` has the source of the app icon and logo

## Support and privacy

For help, see [SUPPORT.md](SUPPORT.md). Finesse collects no data; [PRIVACY.md](PRIVACY.md) explains what it sends to your own server and what it keeps on the Apple TV.

## Licence

Finesse is free software under the GNU Lesser General Public License, version 3. See [COPYING.LESSER](COPYING.LESSER), and [COPYING](COPYING) for the GNU General Public License it builds on.

Copyright 2026 Josh Finlay, Athena Networks.

Finesse includes third-party libraries under their own licences, including mpv and FFmpeg under the LGPL. The app lists each one with its full licence text under Settings, Licences. The scripts and patches that build those libraries are in `tvos-deps/`.

## Not affiliated with Jellyfin

Finesse is an independent client. It isn't made, endorsed or supported by the Jellyfin project. Jellyfin is a trademark of its owners. Finesse also has no connection with Plex, whose apps it takes its layout ideas from.
