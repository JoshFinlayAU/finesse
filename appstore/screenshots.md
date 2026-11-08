# Screenshots

## Requirements

tvOS App Store screenshots are 1920x1080 or 3840x2160, in PNG or JPEG with no transparency. A listing takes 1 to 10. Ours come from `DemoServerUITests` on the `Finesse Apple TV 4K` simulator at 3840x2160, so they're ready to upload as they are.

## Where they are

- **Location:** not in the repo. They're 6 to 8 MB each, and the gallery rule keeps screenshots out of git. The 2026-11-09 set, 11 PNGs from `as-01` to `as-11`, is kept outside the repo, and the #556 report says where.
- **Recreating them:** run the test with `DEMO_URL`, `DEMO_USERNAME` and `DEMO_MOVIE`. See `review-notes.md`.
- **Content:** everything comes from Jellyfin's public demo, which holds old films, mostly public domain in the US, and Creative Commons shorts. Dracula (1931) is the exception, so see below. Nothing comes from our server, and the user picker shows only the demo's "demo" user.

## Proposed set and order

The first three appear in search results, so they carry the listing.

| Order | Capture | Shows | Notes |
|---|---|---|---|
| 1 | `as-04-home-row` | Home: billboard with title art, Play and More Info, Continue Watching | The strongest first image. The billboard picks a title at random, and this set shows Dracula (1931), which is probably under US copyright until 2027. **Recapture** until it picks something else, such as Night of the Living Dead or Caminandes |
| 2 | `as-05-movies` | Movies grid with sort and filter | "The Boy in the Plastic Bubble" poster shows John Travolta. A 1976 TV film's poster is a possible likeness or rights issue, so prefer a crop or a capture where it isn't first. One option is sorting by year descending so Caminandes leads |
| 3 | `as-08-detail` | A detail page: Caminandes: Llamigos | Blender Foundation, CC-BY. The art is bright and clear |
| 4 | `as-10-bar` | The player's control bar over video | This set shows Dracula's title card, "Carl Laemmle presents", so **recapture** it on another film |
| 5 | `as-11-info` | The player's Info panel | Same issue as 4: Dracula's credits behind the panel. Optional |
| 6 | `as-07-search` | Search with results | |
| 7 | `as-02-user-picker` | Who's Watching | Shows Quick Connect and user switching |
| 8 | `as-01-server-entry` | Connect to your server | Plain but explains the model. Optional |

Not proposed: `as-09-playing`, which shows Dracula with nothing on screen; `as-03-home`, which is captured before the artwork loads, and `as-06-shows`, which has only one series.

## Still to decide

- **Text overlays:** Apple allows captions over screenshots. None are made here.
- **Fake-server mode:** it gives seeded data with no artwork, which looks worse than the demo, so it isn't used. Its one use would be showing Skip Intro and Up Next, which the demo can't trigger. Gallery numbers 32 to 34 are fake and seeded versions of those.
- **Credits:** Caminandes is CC-BY. A credit line in the description, such as "Caminandes by the Blender Foundation, CC-BY", would cover the attribution. This is the owner's call.

## Recapture

`DemoServerUITests` plays whatever Home's billboard picks. For the final set, either run it until the billboard picks a safe title, or set `DEMO_MOVIE` and add a play-from-detail step once #600's focus fix lands. The second is better, because the title is then fixed.
