# App Store submission package

Finesse 1.0 for tvOS. Nothing in this folder has been entered into App Store Connect yet. `asc_apply.py` does that in one go, after the owner's word.

| File | What it covers | Status |
|---|---|---|
| `metadata.md` | Subtitle, promotional text, description, keywords, category, URLs, copyright, price and availability | FINAL |
| `../PRIVACY.md`, `../SUPPORT.md` | The privacy policy and support contact, at the repo root | FINAL |
| `privacy-policy.md` | Where the policy lives, and the App Privacy answers ("Data Not Collected") | FINAL |
| `age-rating.md` | Questionnaire answers, giving 4+, compared with other players | FINAL |
| `export-compliance.md` | Encryption answers, with France excluded | FINAL |
| `eula.md` | The custom licence agreement | FINAL |
| `review-notes.md` | Notes for App Review, the demo server and its test result | FINAL |
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
| Support | GitHub Issues, plus support@athenanetworks.com.au and 1300 409 252 |
| Licence agreement law | Queensland |

The manager's defaults in #623:

- **Demo server:** Jellyfin's public demo only.
- **Text:** subtitle option 1, and keywords without competitor names.
- **Age rating:** 4+ as answered.
- **Server version:** Jellyfin 12.4 or later, the lowest version tested.

## Still needed from the owner

1. **A legal read of the licence agreement** is recommended, because of the tension between Apple's minimum terms and the LGPL. See `risks.md`, item 3.
2. **Approval of the final screenshot set.**
3. **A go-ahead to run `asc_apply.py`.** After that, the App Privacy answers in the web UI and Submit for Review stay the owner's own steps.
4. **Optional: a phone number that works from outside Australia.** 1300 numbers can't be dialled internationally, so App Review can only use the email.
