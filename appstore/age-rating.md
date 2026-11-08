# Age rating answers

App Store Connect's questionnaire was updated in 2025. The tiers are now 4+, 9+, 13+, 16+ and 18+, and it asks new questions about in-app controls, capabilities, medical or wellness topics and violent themes. The exact wording should be read in App Store Connect when the answers go in. The headings below follow the published groups.

## Principle

The questionnaire rates content that the app itself contains or shows. Finesse ships no media. Everything it plays comes from a server the user runs or was given, the way a file player like VLC or Infuse works. Answer for the app itself, and say plainly in the review notes that content comes from the user's server.

## Answers

| Question group | Answer | Why |
|---|---|---|
| Violence of any kind (cartoon, realistic, prolonged, graphic) | None | The app contains no media |
| Violent themes (new) | None | The app contains none |
| Guns or other weapons (new) | None | The app contains none |
| Sexual content or nudity, graphic or not | None | The app contains none |
| Profanity or crude humour | None | The app contains none |
| Mature or suggestive themes | None | The app contains none |
| Horror or fear themes | None | The app contains none |
| Alcohol, tobacco, drugs | None | The app contains none |
| Simulated gambling, contests | None | The app has neither |
| Medical or treatment information, wellness topics (new) | None | |
| Unrestricted web access | No | No browser and no web views. tvOS has no `WKWebView` |
| User-generated content | No | No sharing or posting between users. The server is the user's own library, not a service we run |
| Messaging or chat | No | |
| Advertising | No | |
| In-app controls, such as parental controls (new) | No | The app has no controls of its own. Jellyfin servers enforce parental ratings for each user on the server. This could be "Yes" if Apple counts server-enforced limits, but the answer should describe the app, so the answer is "No" |
| Capabilities, such as AI or assistants (new) | None | |
| Age assurance | No | |

These answers produce **4+**. The API field for each is in `asc_apply.py`.

## What comparable players are rated

From the US App Store, checked on 2026-11-09 through Apple's lookup API and the product pages.

| App | Rating | Notes |
|---|---|---|
| VLC media player | 4+ | Plays any file the user supplies, with no in-app controls declared |
| Infuse | 4+ | Plays the user's own files and servers, including Jellyfin. Some storefronts show it "with content restrictions" and list its own parental controls |
| Plex | 4+ "with content restrictions" | Declares in-app parental controls. The page says some content may be rated higher and is managed through those controls |
| Swiftfin, Jellyfin's own client | 4+ | |
| Streamyfin, JellyTV, Tomo TV, Moonfin (Jellyfin clients) | 4+ | |
| VidHub | 4+ | |

User-supplied media doesn't push Apple to a higher rating for any of them. Apple rates what the app itself contains, and players of a user's own library are rated 4+ across the board, Jellyfin clients included.

## Decision: FINAL

The rating is 4+, from the answers above, by the manager's default in #623 after this check. There's no override and no Korea override.

`parentalControls` stays false. Jellyfin servers do enforce each user's maximum parental rating, and Finesse shows only what the server returns. Plex declares controls of its own, but Finesse has none in the app, so declaring them would overstate it. The review notes say the server operator controls what each user can see.

The demo server App Review will use holds old films, including "Night of the Living Dead" (1968), a horror film with some violence. The review notes say that content belongs to the server, not the app.

Sources: Apple, "Updated age ratings in App Store Connect", https://developer.apple.com/news/?id=ks775ehf. Apple's iTunes Search and Lookup API, `itunes.apple.com/lookup` and `/search`, for the ratings above.
