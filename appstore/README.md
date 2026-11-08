# App Store submission package

These are drafts for Finesse 1.0 on tvOS, for the owner to review. Nothing in this folder has been entered into App Store Connect.

| File | What it covers |
|---|---|
| `metadata.md` | Subtitle, promotional text, description, keywords, category, URLs and copyright |
| `privacy-policy.md` | Privacy policy text, where to host it, and the App Privacy answers |
| `age-rating.md` | Age rating questionnaire answers |
| `export-compliance.md` | Encryption answers, and what to do about `ITSAppUsesNonExemptEncryption` |
| `review-notes.md` | App Review notes, demo server options, and the demo server test result |
| `screenshots.md` | Which screenshots to use, and how they were made |
| `risks.md` | What could cause a rejection or a later problem |

## Owner decisions needed

1. **Demo server:** use Jellyfin's public demo, or also run our own review server as a fallback. See `review-notes.md`.
2. **Price:** free is recommended.
3. **Regions:** all regions, or every region but France. France needs a French encryption declaration because of the bundled OpenSSL. See `export-compliance.md`.
4. **URLs:**
   - **Support:** GitHub Issues, plus a contact email.
   - **Privacy policy:** `PRIVACY.md` on GitHub.
   - **Marketing:** a GitHub Pages site, or none.
5. **Support email address:** for the privacy policy, the support page and App Review contact.
6. **Copyright holder:** Josh Finlay or Athena Networks, matching the seller name.
7. **Age rating:** 4+ as answered, or a higher minimum set by hand. See `age-rating.md`.
8. **Licence agreement:** Apple's standard one, or a custom one stating that the open-source licences take precedence. See `risks.md`, item 3.
9. **Certificate verification:** whether 1.0 ships with mpv's certificate verification still off. See `risks.md`, item 4.
10. **Subtitle and keywords:** pick from the options in `metadata.md`.
11. **Minimum Jellyfin version** for the description. Only 12.4.0 has been tested.
12. **Final screenshots:** approve the set in `screenshots.md`. Three need recapturing away from Dracula (1931).
