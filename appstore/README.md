# App Store submission package

Finesse 1.0 for tvOS. Nothing in this folder has been entered into App Store Connect yet. `asc_apply.py` does that in one go, after the owner's word.

| File | What it covers | Status |
|---|---|---|
| `metadata.md` | Subtitle, promotional text, description, keywords, category, URLs, copyright, price and availability | FINAL, except the support email |
| `../PRIVACY.md` | The privacy policy, at the repo root | FINAL, except the contact email |
| `privacy-policy.md` | Where the policy lives, and the App Privacy answers ("Data Not Collected") | FINAL |
| `age-rating.md` | Questionnaire answers, giving 4+, compared with other players | FINAL |
| `export-compliance.md` | Encryption answers, with France excluded | FINAL |
| `eula.md` | The custom licence agreement | FINAL, except the contact and governing-law placeholders |
| `review-notes.md` | Notes for App Review, the demo server and its test result | FINAL, except the reviewer contact |
| `screenshots.md` | Which 8 screenshots, in what order, and how they're made | FINAL once the owner approves the set |
| `risks.md` | What could cause a rejection or a later problem | Current |
| `asc-api.md`, `asc_apply.py` | The App Store Connect API calls that enter all of it | Drafted and checked offline, not run |

## Owner decisions, 2026-11-09

| Area | Decision |
|---|---|
| Price | Free |
| Availability | Every territory except France, with new territories off |
| Copyright | 2026 Athena Networks, also the responsible party in the privacy policy |
| Licence agreement | Custom, keeping the open-source rights intact |
| mpv certificate verification | Stays off for 1.0, as a known issue |
| Support | GitHub Issues, with no email given yet |

The manager's defaults in #623:

- **Demo server:** Jellyfin's public demo only.
- **Text:** subtitle option 1, and keywords without competitor names.
- **Age rating:** 4+ as answered.
- **Server version:** Jellyfin 12.4 or later, the lowest version tested.

## Still needed from the owner

1. **Contact details:** a contact email, a phone number and a postal address for Athena Networks.
   - **Licence agreement:** Apple's minimum terms require all three.
   - **App Review:** it needs a contact name, phone and email.
   - **Privacy policy:** it has a marked place for the email.
2. **Governing-law state** for the licence agreement, or agreement to drop that clause.
3. **A legal read of the licence agreement** is recommended, because of the tension between Apple's minimum terms and the LGPL. See `risks.md`, item 3.
4. **Approval of the final screenshot set.**
5. **A go-ahead to push to GitHub,** so the privacy and support URLs work.
6. **A go-ahead to run `asc_apply.py`,** then the App Privacy answers in the web UI and Submit for Review, which stay the owner's own steps.
