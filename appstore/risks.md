# Review risks

Ranked by how likely each one is to cause a rejection or a later problem. None of them is known to block approval.

## 1. Guideline 2.1, a reviewer who can't sign in

**Likelihood: high without a plan.**

App Review can't reach our LAN test server, and a server client that can't connect gets rejected under 2.1 (App Completeness) or 4.2 (Minimum Functionality).

**Mitigation:** give review a public demo server and account in the review notes. See `review-notes.md`.

- **Jellyfin's demo:** user `demo`, blank password. It worked in our simulator test, but it's run by the Jellyfin project with no availability promise. It has been reset and its version changed without notice before.
- **Shared state:** the account is shared with the public. Anyone can change its settings, such as the audio language preference, which was set to German when checked on 2026-11-09, or leave half-watched items.
- **Fallback:** an owner-run server would remove all of that.

## 2. Guideline 5.2.3, audio and video access

**Likelihood: medium.**

Reviewers reject apps that seem to give unauthorised access to third-party streams or catalogues. A media player that connects to "a server" can trigger this if the reviewer thinks it reaches someone else's content.

**Mitigations:**

- **Review notes:** say plainly that Finesse plays only media on a server the user runs, and has no catalogue or content of its own.
- **Demo content:** what review will see is mostly public domain in the US, such as "Night of the Living Dead" (1968). The Caminandes shorts are the Blender Foundation's, under Creative Commons Attribution.
- **Dracula (1931):** an exception. 1931 works only enter the US public domain on 1 January 2027, so the demo's copy is probably still under copyright today. It's the Jellyfin project's choice, not ours, but a reviewer could land on it, since Home's billboard picked it in our run. Keep it out of screenshots. Submitting after 1 January 2027 makes this moot.
- **Screenshots:** use only that content, or the fake-server mode. See risk 6.
- **Precedent:** Infuse and Plex ship on tvOS as players of a user's own server. Before quoting it to Apple, check whether Swiftfin, Jellyfin's own Apple client, has a current tvOS App Store listing. It wasn't verified here.

## 3. LGPL v3 and the App Store terms

**Likelihood of a rejection: low. Likelihood of a licence question: medium.** This is a legal matter, not a technical one, and the owner may want advice.

- **The concern:**
  - LGPLv3 forbids "further restrictions" on the rights it grants, and requires that users can relink the app with a modified library.
  - For consumer devices it also requires the installation information needed to run that relinked app, through LGPLv3 4(e) and GPLv3 section 6.
  - Apple's standard licence agreement limits copying and use, and on its own an Apple TV only installs App Store software.
  - VLC was pulled in 2011 over the GPL version of this problem.
- **Our position:**
  - **Linking:** the LGPL libraries (FFmpeg, mpv, libass, FriBidi and the rest of our `tvos-deps` build) are dynamic frameworks. They're separate files in the app bundle and can be swapped in a rebuilt app.
  - **Source:** Finesse's own source is public under LGPLv3 at github.com/JoshFinlayAU/finesse.
  - **Rebuilding:** the repo carries the scripts, pinned versions, checksums and patches that rebuild every LGPL library from source (`tvos-deps/`), plus `project.yml` to build the app.
  - **Installing:** anyone with Xcode and an Apple developer account can build and install a modified copy on their own Apple TV. That serves as the installation route. Nobody has checked whether a free Apple ID's personal team can install on Apple TV, or for how long.
  - **Source offer:** the in-app Licences screen gives the source offer, as of #555 (agent-1).
  - **OpenSSL:** it's Apache 2.0 and has no such conditions.
- **Remaining gaps:**
  1. **The licence agreement:** Apple's standard licence still applies to the App Store copy. One mitigation is a custom licence agreement in App Store Connect. It would say that the open-source components, and Finesse itself, are licensed under their own licences, and that nothing in the agreement limits those rights. Apple allows a custom licence, so this is an owner decision.
  2. **Copyright holders:** the owner is the sole copyright holder of Finesse's own code, so its LGPL licence can't conflict with itself. Outside contributors would change that, so a contributor note may be wanted before accepting pull requests.
  3. **Release tags:** source for each shipped build should be tagged in the repo, so "the source for this version" is exact. Agent-3 could tag the commit each archive was built from.

## 4. ATS and certificate checks

**Likelihood: low to medium.**

- **Plain HTTP:** `NSAllowsArbitraryLoads` is set, by the owner's decision. Review may ask for a justification, and the wording is in `memory/privacy-and-test-secrets.md`, also used in `review-notes.md`.
- **Certificates:** mpv doesn't verify certificates for HTTPS streams. That's a known issue in `tvos-deps/README.md`, and the owner chose to revisit it before release. Review is unlikely to test it, but it's a security weakness in a shipped build: someone on the network could impersonate an https server for mpv-played streams, though not for sign-in or the API, which go through `URLSession` with full checks. Decide whether 1.0 ships with it.

## 5. Name and trademark

**Likelihood: low for review, but a business risk.**

- **The Finesse name:** "FINESSE TV", an Android IPTV app, and others use the name. No official trademark register has been searched, according to CLAUDE.md. The App Store record already reserves "Finesse" on Apple's side.
- **Jellyfin:** used only to describe compatibility. No logo, plus a "not affiliated" line in the description. Apple's guideline 2.3.7 and 5.2.1 checks look for third-party marks used as if endorsed.
- **Keywords:** naming Plex or Emby there invites a 2.3.7 rejection. `metadata.md` recommends against it.

## 6. Screenshots

**Likelihood: low, if followed.**

- **Real content:** screenshots must show the app in use. Anything with commercial film artwork risks 5.2.2 (third-party content) or a rights query, so use only demo-server content (public domain or Creative Commons) or fake-server mode.
- **Demo artwork:** the posters come from public metadata sites through the server. For public-domain films they're mostly old posters or stills, which are generally fine. Caminandes artwork is the Blender Foundation's, under CC-BY, and CC-BY asks for attribution. An App Store screenshot has no room for credits, so prefer screens where Caminandes isn't the main image, or credit it in the description. This is a small point, so it's listed for the owner.
- **Household data:** never use a screenshot of the real server's user picker. The demo's picker shows only "demo".

## 7. Top Shelf

**Likelihood: low.**

- **Signed out:** the extension returns no content, and tvOS shows the static Top Shelf image from the asset catalogue (`Top Shelf Image` and `Top Shelf Image Wide`), which both exist. Apple wants the shelf to show something meaningful, and the static image counts.
- **Signed in:** it shows Continue Watching and Next Up from the active user, with deep links into the app. Review will see that once they've signed in to the demo and started something.
- **Not checked on a real Apple TV:** whether the shelf's artwork loads over plain HTTP on device, and how it behaves after a reboot. See `memory/top-shelf.md`.

## 8. Smaller items to fix before the archive

These are for agent-1 or agent-3.

- **Detail page focus on a slow server:** found in the #556 demo runs. On the demo server, a detail page opened from Search showed no focus on Play, and Up then acted on the Search screen hidden underneath. The probable cause is that `.defaultFocus` in `ItemDetailView.swift` only applies once loading finishes. A reviewer on a slow link would hit it. Agent-1 has the fix as a new task, and it is **pending**. It must land before the archive that goes to review.
- **Version:** already fixed. The app and the extension are 1.0 from build settings since `b8f56d3`.
- **Validation:** App Store validation hasn't been run (`memory/privacy-and-test-secrets.md`). Expect it to check the privacy manifests, including OpenSSL's, since Apple's list of SDKs needing a manifest and signature names OpenSSL. Our OpenSSL is our own build, so it can't carry the upstream signature. Apple's rule applies to the listed SDKs as binaries, so validation will show whether it treats our build as one. Agent-3's archive will be the first test.
- **Local network prompt:** `NSLocalNetworkUsageDescription` is present. On first connection to a LAN server, tvOS asks for local network access. The demo server is public, so review won't see the prompt.
- **Back button:** check the Back/Menu path from every screen once more on the release build. tvOS review checks that Menu on the root screen returns to the Home Screen.
