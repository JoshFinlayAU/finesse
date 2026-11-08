# Finesse — software spoke

A polished tvOS Jellyfin client with near feature parity with Plex. Its information architecture follows the pre-redesign Plex app, and its visual language is Liquid Glass.

Inherits the hub's global rules (see `../../CLAUDE.md`). This file adds spoke-specific context.

## Decisions

These are the owner's choices. Don't change them without asking.

| Area | Decision |
|---|---|
| Playback | Hybrid: AVPlayer first, libmpv/FFmpeg fallback |
| Playback package | Our own dynamic mpv and FFmpeg build, with FFmpeg under LGPLv3 and OpenSSL for TLS 1.3, and no GPL components. The scripts and licence record are in `tvos-deps/` |
| mpv certificate verification | Off for 1.0, confirmed by the owner on 2026-11-09. A known issue, listed in `appstore/risks.md`, to revisit after 1.0 |
| UI | SwiftUI first, UIKit where needed |
| Minimum OS | tvOS 26; no back-deployment or availability shims for older versions |
| Design | Full Liquid Glass; Plex for structure only |
| v1 scope | Core video experience first |
| Builds | Remote Mac `fin-mac` over SSH; code synced with rsync, then `xcodebuild` |
| Devices | Simulator plus a real Apple TV |
| Test server | Existing Jellyfin server, test user only |
| Distribution | TestFlight first, kept App Store-ready |
| Branding | Concept 04 Palace, nested picture-palace arches with the FINESSE wordmark. It has no letter, so pair it with the wordmark wherever the mark alone wouldn't say Finesse. Source and the tvOS asset requirements are in `branding/` |
| Licence | LGPLv3, open source at github.com/JoshFinlayAU/finesse, which is public. `COPYING.LESSER` and `COPYING` hold the texts, and the in-app licences screen lists Finesse and points its source offer at the repo |
| Bundle ID | `au.com.athenanetworks.finesse`. Registered in the developer portal on 2026-11-07. The owner approved an App Store Connect record on 2026-11-09: name Finesse, SKU `finesse-tvos`, tvOS, English (Australia). The owner created it in the web UI, because the API can't create app records. Apple ID `6832351387`, with version 1.0 for tvOS waiting in Prepare for Submission, checked through the API on 2026-11-09 |
| Apple team | `4S7BG5A4XV` |
| Plain HTTP | Allowed to any server (`NSAllowsArbitraryLoads`), because servers are user-configured and self-hosted |
| App Store availability and price | Free, in every territory except France, chosen by the owner on 2026-11-09. Leaving out France avoids the French encryption declaration that the bundled OpenSSL would need. See `appstore/export-compliance.md` |
| App Store copyright | "2026 Athena Networks", which the store shows with the copyright sign, chosen by the owner on 2026-11-09. Athena Networks is also the responsible party in `PRIVACY.md` |
| App Store licence agreement | A custom licence agreement, not Apple's standard one, chosen by the owner on 2026-11-09. It keeps the open-source licences' rights intact. The text is in `appstore/eula.md` |

## Stack

- Swift and SwiftUI on the tvOS 26 SDK, using Xcode on `fin-mac`. Use the Observation framework and structured concurrency.
- UIKit is for what SwiftUI can't do well: player view hosting, `AVPlayerViewController`, the mpv render surface, and specific focus problems. Wrap it in `UIViewRepresentable` or `UIViewControllerRepresentable` and keep it out of feature code.
- Playback uses AVFoundation/AVKit plus libmpv/FFmpeg, through our own 14 dynamic xcframeworks: Libmpv, six FFmpeg libraries, OpenSSL, Libuchardet, Libass, Libfribidi, Libdav1d, Libplacebo and MoltenVK. Binaries are never committed. See "Playback frameworks" below.
- Jellyfin access goes through the official `jellyfin-sdk-swift` if it covers the target server version. Keep it behind our own client layer so views never touch SDK types.
- Swift dependencies use Swift Package Manager; commit `Package.resolved`.
- Every shipped component is listed in `Finesse/Resources/Licences/licences.json` for the in-app licences screen. The unit plan fails if it falls behind `Package.resolved` or `tvos-deps/versions.sh`, so update its entry and text with any version change. MoltenVK's own dependencies aren't covered by that check.
- Keep `project.yml` (XcodeGen) as the project source of truth and generate the `.xcodeproj` on the Mac. `.pbxproj` files are impractical to edit from Linux, so don't commit a generated one.

## How to run / build / test

This Linux workspace can't compile or run anything tvOS. **A change is only verified once it has built and passed on `fin-mac`.** Linux is the source of truth and `~/Developer/Finesse` on the Mac is a disposable copy, so never edit there.

### First-time setup

Done on 2026-11-06, with the Apple TV added on 2026-11-07.

- `fin-mac` is in `~/.ssh/config` on Linux with key auth. Its login and address are in `memory/mac-setup.md`. It also hosts production iMessageAI and other spokes' builds, so touch only `~/Developer/Finesse` and our own simulators.
- Xcode 27.2 and XcodeGen were already on the Mac, and `~/Developer/Finesse` exists.
- tvOS 27.2 and 26.5 simulator runtimes are installed. Our simulators are `Finesse Apple TV 4K` (27.2, the default) and `Finesse Apple TV 4K 26` (26.5, the nearest installed to the minimum OS). The 26.5 one needs `OS=26.5` in the destination, because `xcodebuild` otherwise assumes `OS=latest` and reports no matching device.
- The `Lounge Room` Apple TV is paired and registered, and device builds sign headlessly with the `aisbuild` keychain. No Xcode account sign-in is needed. Details are in `memory/mac-setup.md`.

### Playback frameworks

A clean checkout can't build until `../FinesseDeps/dist` holds the xcframeworks, because `project.yml` links them from there and the app has no fallback. On `fin-mac` that's `~/Developer/FinesseDeps/dist`, outside the synced copy, so `--delete` doesn't touch it.

To fill it, follow "Building" in `tvos-deps/README.md` on the Mac. From an empty work folder this took about 10 minutes on 2026-11-07, needs no sudo and doesn't change Homebrew. No published archive exists yet, and the proposal for one in that README hasn't been approved. Rebuild after changing `tvos-deps/versions.sh` or its patches.

### Sync

Run from the spoke root:

```sh
rsync -az --delete --exclude-from=.rsyncignore ./ fin-mac:Developer/Finesse/
```

`.rsyncignore` must exclude at least `.git/`, `.env.local`, `.claude/`, `.aisandbox/`, `memory/`, `skills/`, `build/`, `DerivedData/` and `*.xcodeproj/`. Keep the trailing slashes in the command, and never point `--delete` at any other path.

### Build and unit test

Non-interactive SSH doesn't load Homebrew's PATH, so set it explicitly.

```sh
ssh fin-mac 'export PATH=/opt/homebrew/bin:$PATH; cd ~/Developer/Finesse && xcodegen generate && \
  xcodebuild build-for-testing -project Finesse.xcodeproj -scheme Finesse \
  -destination "platform=tvOS Simulator,name=Finesse Apple TV 4K" -derivedDataPath build'

ssh fin-mac 'cd ~/Developer/Finesse && xcodebuild test-without-building -project Finesse.xcodeproj -scheme Finesse \
  -destination "platform=tvOS Simulator,name=Finesse Apple TV 4K" -derivedDataPath build'
```

These names are ours, so they don't change between Xcode versions. To see them, run `ssh fin-mac xcrun simctl list devices available`.

### Integration tests

The test user's URL and credentials live in a gitignored `.env.local` at the spoke root on Linux. This is a deliberate choice for these low-privilege test credentials only. The file is never rsynced or written to the Mac; values are passed at test time over SSH stdin, which keeps them out of process arguments.

```sh
sed 's/^/TEST_RUNNER_/' .env.local | ssh fin-mac 'set -a; . /dev/stdin; set +a; cd ~/Developer/Finesse && \
  xcodebuild test-without-building -project Finesse.xcodeproj -scheme Finesse \
  -testPlan Integration \
  -destination "platform=tvOS Simulator,name=Finesse Apple TV 4K" -derivedDataPath build'
```

- `xcodebuild` strips the `TEST_RUNNER_` prefix, so tests read `JELLYFIN_URL` and the other variables as written in `.env.local`.
- Keep values shell-safe and quoted, with no comment lines in the file.
- Skip integration tests when the variables are absent, and keep them in their own test plan so unit tests stay offline.
- Don't log credentials or tokens, including in test output.
- One accepted exception, for these low-privilege test accounts only: test credentials can't be kept out of two places. `runningboardd` and `CoreSimulatorBridge` write process environments to the simulator's unified log on every run, and result bundle action logs also hold them. Delete result bundles after use, and erase our simulators periodically with `xcrun simctl shutdown "<name>"` then `xcrun simctl erase "<name>"`. This doesn't extend to any other credential.

### UI flow tests

`-testPlan UI` drives the real app with the Siri Remote API (`XCUIRemote`) and keeps screenshots in the result bundle. It's the only way to send remote input to the simulator from here.

- `FakeServerUITests` needs no server. It launches with `-FinesseFakeServer`, a DEBUG-only mode with two signed-in users and seeded hubs.
- `SignInFlowUITests` signs in to the test server using the same stdin credentials as the integration tests, and skips without them. Reset first so it starts signed out: `xcrun simctl keychain "Finesse Apple TV 4K" reset`.
- `TwoUserSwitchingUITests` and the integration `TwoUserSwitchingTests` need `JELLYFIN_USERNAME_2` and `JELLYFIN_PASSWORD_2` in `.env.local` for the second test user, and skip without them.
- `TopShelfUITests` drives the simulator's Home Screen rather than the app, so it only runs when asked. Add `TEST_RUNNER_FINESSE_TOP_SHELF_TEST=1` to the stdin values along with the credentials, and name it with `-only-testing:FinesseUITests/TopShelfUITests`. The Home Screen reports nothing about the shelf to XCTest, so review the `shelf-` screenshots for what it shows. The assertions only prove what choosing an item does. It changes only the test user's own state and undoes it.
- The real user picker shows household names from `/Users/Public`, so never commit or quote those screenshots.

### Real Apple TV

`scripts/apple-tv-build.sh` is the device build path. It handles the headless signing and the framework re-signing that a real device insists on, so don't build for the device with plain `xcodebuild`.

Hold `fin-mac-build` and `lounge-room-apple-tv`, sync, then run this from the spoke root. Leave out `install` to build and sign without touching the TV, which is the household's, so don't play anything on it unprompted. `install` ends a running copy of the app and doesn't open the new one, so check first that nobody is watching. Add `launch` after it to open the app.

```sh
ssh fin-mac 'bash -s install' < scripts/apple-tv-build.sh
ssh fin-mac 'xcrun devicectl device capture screenshot --device "$(cat ~/.config/finesse/apple-tv-udid)" --destination /tmp/fin-tv.png' && scp fin-mac:/tmp/fin-tv.png /tmp/fin-tv.png
```

Sign off any playback change on the real device. The simulator doesn't represent hardware decode, HDR/Dolby Vision, display mode switching, audio passthrough or Siri Remote feel.

### Checking UI

Capture the simulator screen and pull it back to review. Name our simulator rather than using `booted`, because other spokes may have one running on the same Mac:

```sh
ssh fin-mac 'xcrun simctl io "Finesse Apple TV 4K" screenshot /tmp/fin.png' && scp fin-mac:/tmp/fin.png /tmp/fin.png
```

For UI changes, state which screens were checked and how. Focus behaviour can't be fully judged from a still image, so say when it needs a hands-on check.

### Release

TestFlight uploads and any App Store Connect change are outward-facing, so confirm each one first. Archive and upload from `fin-mac`.

`scripts/app-store-archive.sh` makes the Release archive and the App Store export, checks what Apple will receive, and with `validate` has Apple validate it. It never uploads. Hold `fin-mac-build`, sync, then run this from the spoke root with the App Store Connect API key's IDs, which stay out of the repo:

```sh
{ echo "export ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id>"; cat scripts/app-store-archive.sh; } | ssh fin-mac 'bash -s validate'
```

- It signs with the Apple Distribution identity in the `aisbuild` keychain and the `Finesse tvOS App Store` and `Finesse Top Shelf tvOS App Store` profiles.
- The version comes from `MARKETING_VERSION` in `project.yml`. The build number defaults to the UTC time as `YYYYMMDD.HHMM`, or set `FINESSE_BUILD_NUMBER`.
- Its last line is the upload command for that export. Run it only once the owner says go.
- Our frameworks ship without dSYMs, so an upload warns about missing symbols for them.

## v1 scope

**In:**
- Server connection and sign-in, including Quick Connect
- User switching
- Home hubs: Continue Watching, Next Up, Recently Added
- Movie and TV library browsing with sort and filter
- Search
- Movie, show, season and episode detail pages
- Playback with resume and progress reporting
- Audio and subtitle selection
- Skip intro/credits where the server has media segments
- Next-episode autoplay

**Deferred; don't build without asking:** music, photos, Live TV/DVR, SyncPlay, offline downloads, and discovery or recommendations beyond what the server provides.

## Conventions

### Design

- **Plex supplies structure:** navigation model, hub rows, detail page hierarchy, and what appears where and in what order.
- **Liquid Glass supplies appearance:** materials, controls, tab bar, depth and motion. Where the two conflict, Liquid Glass wins.
- Prefer system components, which adopt Liquid Glass automatically. Use `glassEffect` and related APIs sparingly on custom chrome. Don't set `UIDesignRequiresCompatibility` or recreate Plex's opaque styling.
- Don't use Plex's logos, artwork, assets or brand colours.
- Every interactive element needs deliberate focus behaviour. Design for 10-foot viewing and Siri Remote input, and test the Back/Menu path from every screen.

### Playback

- All playback goes through one `PlaybackEngine` protocol with AVPlayer and mpv implementations. UI never talks to an engine directly.
- Engine choice lives in one place, a `PlaybackRouter`. Default to AVPlayer for anything it can play natively. Use mpv for what it can't, such as MKV containers, DTS/TrueHD audio, or PGS/ASS subtitles. Use server transcoding as the last resort.
- The device profile sent to Jellyfin must match what the two engines can actually play. Update it whenever routing changes.
- Both engines must present the same player controls and report progress the same way.

### Code

- Organise by feature, with separate layers for the Jellyfin client, playback and shared UI. Views stay free of networking and engine logic.
- Set a valid module name (`PRODUCT_MODULE_NAME = FinEsse`), because the hyphen in `Finesse` isn't valid in a Swift module name. Use `FinEsse` for code identifiers and `Finesse` for the user-facing name.
- Write new tests with Swift Testing where it fits. Unit tests use recorded fixtures rather than a live server.
- Commit to `main` with imperative commit messages. Short-lived branches are optional.
- The repo is public. Before pushing, check new commits for internal addresses, the Mac login, the Apple TV UDID and workspace paths (see `memory/github-remote.md`).

## Gotchas

- **Test server:** it's an existing server, so use only the test user. Don't use admin endpoints or credentials, and don't change server settings, libraries, media or other users. Tests may only change the test user's own state, such as watch progress or favourites, and should tolerate library contents changing.
- **Jellyfin API:**
  - Times are in ticks, at 10,000,000 per second.
  - Sessions need a stable `DeviceId` and a `MediaBrowser` authorization header.
  - Report start, progress and stop, or resume and Next Up will drift.
  - Check the behaviour against the test server's version rather than assuming it from docs.
- **libmpv/FFmpeg licensing:** our own dynamic build, with FFmpeg under LGPLv3 and OpenSSL for TLS 1.3 by the owner's decision, which replaced an earlier LGPL 2.1 plan. No GPL components. Track each dependency's licence, since App Store distribution has to meet the LGPL obligations, and keep the source offer in `licences.json` current. Finesse is LGPLv3, so code copied in must have a compatible licence. Treat Swiftfin and other clients as references only, and don't copy their code without checking the licence.
- **App Transport Security:** the app allows plain HTTP to any host, by the owner's decision. `NSAllowsLocalNetworking` must stay out of `Info.plist`, because its presence makes the system ignore `NSAllowsArbitraryLoads`. The App Review justification is in `memory/privacy-and-test-secrets.md`. AVPlayer and mpv make their own connections, so test both.
- **tvOS storage:** local storage can be purged and `UserDefaults` is small. Keep tokens in the Keychain, treat image and metadata caches as disposable, and don't assume files persist.
- **tvOS frameworks:** there's no `WKWebView`, so sign-in and help flows must be native.
- **Display matching:** AVPlayer and mpv handle frame rate and dynamic range differently. Check match-content behaviour for each engine on the real Apple TV.
- **Signing over SSH:** a locked login keychain can cause `errSecInternalComponent` during device or archive builds. Unlocking it or fixing signing on the Mac needs the owner, so ask rather than working around it.
- **Stale builds:** after changing `project.yml` or dependencies, rerun `xcodegen generate`. Files created on the Mac don't sync back and may be removed by `--delete`, so copy anything worth keeping to Linux first.
- **The name:** FINESSE TV, an Android IPTV app, is the closest clash found, and a dance-training app and a pending US filing also use the name. Those came from web searches only. No official trademark register has been searched, including IP Australia and the USPTO, so do that before release.
- **App Store readiness:** keep to public APIs only. Maintain the privacy manifest, including for bundled binaries, and keep usage strings and required icons current so TestFlight builds stay submittable.

## Notes

- Private memory: `memory/`  ·  Spoke skills: `skills/`
- Destructive git ops (force-push, reset --hard, branch deletes) are fine without asking. Make a throwaway branch or note the SHA first so the state is recoverable.

<!-- aisandbox:multi-agent:start -->
## Multi-agent spoke

*Managed by AI Sandbox. Do not edit this section.*

4 Claude agents share this folder: the manager `fin-esse` and the workers `fin-esse-1` to `fin-esse-3`. Your number is in `$AISANDBOX_AGENT`, and the manager is 0.

- **Tasks, messages, reports, claims and rules live in the team database.** Use `aisandbox-agent` for all of it. Run `aisandbox-agent rules` once at the start of a conversation.
- **[aisandbox] means updates are waiting and carries no content:** run `aisandbox-agent inbox` and act on what it shows.
- **The manager delegates and never does the work itself.** Workers do only their task, and claim before changing anything.
<!-- aisandbox:multi-agent:end -->
