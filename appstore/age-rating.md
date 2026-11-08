# Age rating answers

App Store Connect's questionnaire was updated in 2025. The tiers are now 4+, 9+, 13+, 16+ and 18+, and it asks new questions about in-app controls, capabilities, medical or wellness topics and violent themes. The exact wording should be read in App Store Connect when the answers go in. The headings below follow the published groups.

## Principle

The questionnaire rates content that the app itself contains or shows. Finesse ships no media. Everything it plays comes from a server the user runs or was given, the way a file player like VLC or Infuse works. Answer for the app itself, and say plainly in the review notes that content comes from the user's server.

## Answers

| Question group | Answer | Why |
|---|---|---|
| Violence of any kind (cartoon, realistic, prolonged, graphic) | None | The app contains no media |
| Violent themes (new) | None | The app contains none |
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
| In-app controls, such as parental controls (new) | No | The app has no controls of its own. Jellyfin servers enforce parental ratings for each user on the server. This could be "Yes" if Apple counts server-enforced limits, but the answer should describe the app, so the recommendation is "No" |
| Capabilities, such as AI or assistants (new) | None | |
| Age assurance | No | |

These answers should produce **4+**.

## Owner decision

**Option A: 4+, recommended.** It's what the answers produce, and it's honest about the app. This is the usual result for players of a user's own library. The review notes say that content comes from the user's server, and that the server's operator controls what each user can see.

**Option B: set a higher minimum age by hand,** such as 16+ or 18+, using the override Apple added in 2025.

- It guards against a reviewer deciding that a player of arbitrary files deserves a mature rating.
- The cost is that a higher rating hides the app from children's accounts, and from family members whose Screen Time limits stop at a lower age. That matters in a household app with user switching.

The demo server App Review will use holds old public-domain films. One of them is "Night of the Living Dead" (1968), which is a horror film with some violence, and a reviewer could see it. That's another reason the review notes should say the content belongs to the server, not the app.

Source: Apple, "Updated age ratings in App Store Connect", https://developer.apple.com/news/?id=ks775ehf
