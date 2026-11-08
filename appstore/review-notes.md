# App Review information

App Review needs a server to sign in to, and ours aren't reachable from outside, so the notes send reviewers to the Jellyfin project's public demo server. It is run by the Jellyfin project and can change or go down without notice, so check it still works shortly before each submission.

To check it, run the demo-server UI test on a freshly erased simulator. It connects, signs in as `demo`, browses, finds a film through Search and plays it from its detail page, which is the path the notes describe. It reads only these values, passed with the `TEST_RUNNER_` prefix:

```sh
printf 'TEST_RUNNER_DEMO_URL=https://demo.jellyfin.org/stable\nTEST_RUNNER_DEMO_USERNAME=demo\nTEST_RUNNER_DEMO_PASSWORD=\nTEST_RUNNER_DEMO_MOVIE=Llamigos\n' | \
  ssh fin-mac 'set -a; . /dev/stdin; set +a; cd ~/Developer/Finesse && xcodebuild test-without-building \
  -project Finesse.xcodeproj -scheme Finesse -testPlan UI -only-testing:FinesseUITests/DemoServerUITests \
  -destination "platform=tvOS Simulator,name=Finesse Apple TV 4K" -derivedDataPath build'
```

## Sign-in details

Sign-in is required. The account is `demo` with an empty password. If App Store Connect won't accept an empty password, enter "(leave empty)"; the notes explain it.

## Contact

Josh Finlay, support@athenanetworks.com.au, phone 1300 409 252. A 1300 number only works from within Australia, so reviewers will normally use the email.

## Notes

These go in the Notes field, and `asc_apply.py` sends them.

<!-- asc:reviewNotes -->
```
Finesse is a client for Jellyfin, a free, open-source media server that people run on their own computer or NAS. Finesse has no content, catalogue or accounts of its own: it plays only the media on the server the user signs in to, much like a file player.

To review, please use the Jellyfin project's public demo server:

1. On the first screen, enter the server address: https://demo.jellyfin.org/stable
2. Choose Connect.
3. Choose "Other User" and enter the username: demo. Leave the password empty, and choose Sign In.
4. Home, Movies, TV Shows and Search are now available. Any film can be played, for example "Caminandes: Llamigos" from Search.

The demo server is run by the Jellyfin project, not by us, and its content was chosen by that project. If it is unavailable, please let us know through App Store Connect and we will provide another server.

Notes on specific features:
- Top Shelf: once you have started a film, Finesse's Top Shelf on the Home Screen shows Continue Watching and Next Up. Before sign-in it shows our static image.
- Quick Connect is another way to sign in: the Apple TV shows a code, which is approved from another device already signed in to the same server, for example the demo's web page at https://demo.jellyfin.org/stable signed in as demo, under the user menu, then Quick Connect. The password sign-in above is simpler.
- Skip Intro and Skip Credits appear only where the server has marked those segments. The demo server has none.

App Transport Security: Finesse sets NSAllowsArbitraryLoads because users type the address of their own self-hosted server, which the app cannot know in advance. Jellyfin servers default to plain HTTP on port 8096 and are commonly reached by a hostname on a home network, which NSAllowsLocalNetworking does not cover. The app connects only to the server the user entered, and HTTPS is used whenever the user's address uses it.

Privacy: Finesse collects no data. Sign-in details, viewing progress and searches go only to the user's own server, which we neither run nor can access. There are no analytics, ads or tracking.

Encryption: HTTPS through Apple's URLSession, plus OpenSSL (standard TLS) inside the bundled FFmpeg library for streams played by its built-in player.

Finesse is open source under the LGPL v3: https://github.com/JoshFinlayAU/finesse
```
