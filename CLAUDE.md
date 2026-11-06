# Finesse — software spoke

A polished tvOS Jellyfin client with near feature parity with Plex. Its information architecture follows the pre-redesign Plex app, and its visual language is Liquid Glass.

Inherits the hub's global rules (see `../../CLAUDE.md`). This file adds spoke-specific context.

## Decisions

These are the owner's choices. Don't change them without asking.

| Area | Decision |
|---|---|
| Playback | Hybrid: AVPlayer first, libmpv/FFmpeg fallback |
| UI | SwiftUI first, UIKit where needed |
| Minimum OS | tvOS 26; no back-deployment or availability shims for older versions |
| Design | Full Liquid Glass; Plex for structure only |
| v1 scope | Core video experience first |
| Builds | Remote Mac `fin-mac` over SSH; code synced with rsync, then `xcodebuild` |
| Devices | Simulator plus a real Apple TV |
| Test server | Existing Jellyfin server, test user only |
| Distribution | TestFlight first, kept App Store-ready |
| Licence | Private for now; open or closed source to be decided before release |

## Stack

- Swift and SwiftUI on the tvOS 26 SDK, using Xcode on `fin-mac`. Use the Observation framework and structured concurrency.
- UIKit is for what SwiftUI can't do well: player view hosting, `AVPlayerViewController`, the mpv render surface, and specific focus problems. Wrap it in `UIViewRepresentable` or `UIViewControllerRepresentable` and keep it out of feature code.
- Playback uses AVFoundation/AVKit plus libmpv/FFmpeg, ideally through a maintained xcframework package. Confirm that it ships tvOS device and simulator slices before adopting it.
- Jellyfin access goes through the official `jellyfin-sdk-swift` if it covers the target server version. Keep it behind our own client layer so views never touch SDK types.
- Dependencies use Swift Package Manager; commit `Package.resolved`.
- Keep `project.yml` (XcodeGen) as the project source of truth and generate the `.xcodeproj` on the Mac. `.pbxproj` files are impractical to edit from Linux, so don't commit a generated one.

## How to run / build / test

This Linux workspace can't compile or run anything tvOS. **A change is only verified once it has built and passed on `fin-mac`.** Linux is the source of truth and `~/Developer/Finesse` on the Mac is a disposable copy, so never edit there.

### First-time setup

Done on 2026-11-06, except for the last item.

- `fin-mac` is in `~/.ssh/config` on Linux with key auth. It is `user@mac.example`, which also hosts production iMessageAI and other spokes' builds, so touch only `~/Developer/Finesse` and our own simulators.
- Xcode 27.2 and XcodeGen were already on the Mac, and `~/Developer/Finesse` exists.
- tvOS 27.2 and 26.5 simulator runtimes are installed. Our simulators are `Finesse Apple TV 4K` (27.2, the default) and `Finesse Apple TV 4K 26` (26.5, the nearest installed to the minimum OS). The 26.5 one needs `OS=26.5` in the destination, because `xcodebuild` otherwise assumes `OS=latest` and reports no matching device.
- Still needs the owner: sign in to the Apple developer account for this project and pair the Apple TV.

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

### UI flow tests

`-testPlan UI` drives the real app with the Siri Remote API (`XCUIRemote`) and keeps screenshots in the result bundle. It's the only way to send remote input to the simulator from here.

- `FakeServerUITests` needs no server. It launches with `-FinesseFakeServer`, a DEBUG-only mode with two signed-in users and seeded hubs.
- `SignInFlowUITests` signs in to the test server using the same stdin credentials as the integration tests, and skips without them. Reset first so it starts signed out: `xcrun simctl keychain "Finesse Apple TV 4K" reset`.
- The real user picker shows household names from `/Users/Public`, so never commit or quote those screenshots.

### Real Apple TV

```sh
ssh fin-mac 'xcrun devicectl list devices'
ssh fin-mac 'cd ~/Developer/Finesse && xcodebuild build -project Finesse.xcodeproj -scheme Finesse \
  -destination "platform=tvOS,id=<UDID>" -derivedDataPath build -allowProvisioningUpdates'
ssh fin-mac 'xcrun devicectl device install app --device <UDID> \
  ~/Developer/Finesse/build/Build/Products/Debug-appletvos/Finesse.app'
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
- Use short-lived feature branches with imperative commit messages.
- Keep the repo private. Don't add a licence file or push to a public remote until the licence decision is made.

## Gotchas

- **Test server:** it's an existing server, so use only the test user. Don't use admin endpoints or credentials, and don't change server settings, libraries, media or other users. Tests may only change the test user's own state, such as watch progress or favourites, and should tolerate library contents changing.
- **Jellyfin API:**
  - Times are in ticks, at 10,000,000 per second.
  - Sessions need a stable `DeviceId` and a `MediaBrowser` authorization header.
  - Report start, progress and stop, or resume and Next Up will drift.
  - Check the behaviour against the test server's version rather than assuming it from docs.
- **libmpv/FFmpeg licensing:** use LGPL-compatible builds only, with no GPL components. Track each dependency's licence, since App Store distribution and LGPL obligations both feed into the pre-release licence decision. Treat Swiftfin and other clients as references only, and don't copy their code without checking the licence.
- **App Transport Security:** many Jellyfin servers use plain HTTP or local addresses. Keep exceptions as narrow as user-configured servers allow, and be ready to justify them in App Review. AVPlayer and mpv make their own connections, so test both.
- **tvOS storage:** local storage can be purged and `UserDefaults` is small. Keep tokens in the Keychain, treat image and metadata caches as disposable, and don't assume files persist.
- **tvOS frameworks:** there's no `WKWebView`, so sign-in and help flows must be native.
- **Display matching:** AVPlayer and mpv handle frame rate and dynamic range differently. Check match-content behaviour for each engine on the real Apple TV.
- **Signing over SSH:** a locked login keychain can cause `errSecInternalComponent` during device or archive builds. Unlocking it or fixing signing on the Mac needs the owner, so ask rather than working around it.
- **Stale builds:** after changing `project.yml` or dependencies, rerun `xcodegen generate`. Files created on the Mac don't sync back and may be removed by `--delete`, so copy anything worth keeping to Linux first.
- **App Store readiness:** keep to public APIs only. Maintain the privacy manifest, including for bundled binaries, and keep usage strings and required icons current so TestFlight builds stay submittable.

## Notes

- Private memory: `memory/`  ·  Spoke skills: `skills/`
- Destructive git ops (force-push, reset --hard, branch deletes) are fine without asking. Make a throwaway branch or note the SHA first so the state is recoverable.
- Still undecided: bundle ID, Apple team, app icon and branding, and the final licence. Ask rather than inventing them, then record the answers here.

<!-- aisandbox:multi-agent:start -->
## Multi-agent spoke

*Managed by AI Sandbox and rewritten whenever the agent count changes. Do not edit this section.*

**4 Claude agents work this spoke at the same time, in this same folder:** the manager `fin-esse-0-manager` and the workers `fin-esse-1` to `fin-esse-3`. Your number is in `$AISANDBOX_AGENT`, and the manager is 0. AI Sandbox adds your current position to every prompt you receive. Trust it over your memory.

### The manager
- **Delegates everything. It never does the task itself,** however small, and even when the user says "do this": that means get it done. It reads, checks and decides. It does not change files or systems. AI Sandbox refuses its file edits, apart from its own notes in `memory/`. Shell commands are not refused, so that part is on you: use them only to look, never to change anything.
- **Gives every piece of work one owner:** `aisandbox-agent assign next "task"` starts it on a free worker, or queues it until one comes free and then starts it automatically. `aisandbox-agent assign <number> "task"` does the same for one particular worker. Say what the worker owns, what done looks like and everything it needs to know, because it cannot see your conversation. Never give two workers the same files or systems at the same time. Queue overlapping work on the same worker instead.
- **Hears about everything automatically:** each worker's final message and the files it changed, anything the user tells a worker directly, a worker stopping or needing input, and any edit to something another agent has claimed. Act on each one: close the task with `aisandbox-agent done <number> "outcome"`, assign the next piece, or settle the conflict. If nothing is needed, say so in a line and stop. Do not message a worker just to acknowledge it.
- **Keeps the board true.** If a worker is idle with an open task and its last report does not finish it, ask it or reassign the task. `aisandbox-session start fin-esse` restarts a stopped worker.
- **Is the user's view of the team.** Do not say something is finished until every task on the board is closed and you have checked the result yourself. Report what each worker did, what is still open and what you did not verify.

### Workers
- **Work only your assigned task.** If you notice something else that needs doing, send it to the manager rather than picking it up. Starting agents have no task until the manager or the user gives them one.
- **Your final message of each turn goes to the manager automatically,** so do not send it again. Say what is done, what is not, what you verified and anything blocking you.
- **When your task is finished,** release your claims, run `aisandbox-agent done "outcome"` and stop. Do not go looking for more work.
- **The user can talk to you directly.** Do what they ask, and the manager is told automatically. If it overlaps work another agent owns, tell the user and pass it to that agent or the manager instead of doing it yourself.

### Never clobber another agent's work
- **Claim before you change anything**, whether a file, a folder or a system: `aisandbox-agent claim <path-or-system> "why"`.
- **If another agent holds the claim, do not touch it.** Send that agent a message asking it to make the change, or ask it to release the claim. Editing something claimed by another agent alerts you and the manager.
- Re-read a file immediately before editing it. Another agent may have just changed it.
- Release a claim as soon as you finish with it: `aisandbox-agent release <path-or-system>`.
- In git, stage only the files you changed, and never `git add -A`. Do not run `git stash`, `reset`, `checkout`, `clean` or anything else that affects the whole working tree without first agreeing it with the manager, because those commands hit every agent's work.
- Claim a shared service, device or deployment before restarting or changing it.

### Talk to each other
- `aisandbox-agent send <number|manager|all> "message"` queues a message. It reaches the other agent as a prompt once that agent is idle, starting `[message from ...]`.
- `aisandbox-agent status` shows the board: every agent, its task, its last report and the claims.
- Ask for work to be done rather than doing it in another agent's territory.
- Include everything the other agent needs, because it cannot see your conversation.
- Reply only with a result, a question or a problem. Do not send acknowledgements or thanks, because each message costs the other agent a turn.
- Use `aisandbox-agent`, not any built-in messaging tool, so the conversation is on the record.

### Keep a strict audit trail
- This is mandatory. The record is `.aisandbox/agents/audit.log`. It is append-only, so never edit it. Every change you make through a tool is logged automatically, and so is every message.
- The log cannot record why, so you must. Run `aisandbox-agent log "what and why"` when you start a task, make a decision, change a live system, hand something off, and finish.
- Never put a password, token or other secret in a log entry or a message.
- Read `aisandbox-agent audit` before you pick up work that someone else has touched.
<!-- aisandbox:multi-agent:end -->
