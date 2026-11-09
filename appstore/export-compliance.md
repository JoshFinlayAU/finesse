# Export compliance

Finesse uses encryption only to protect its connection to the user's own server. App requests go over HTTPS through Apple's URLSession. Streams played by the built-in mpv player use OpenSSL 3.5, which is bundled inside FFmpeg's networking library and provides standard TLS 1.2 and 1.3. There is no proprietary cryptography.

Because OpenSSL ships in the app rather than coming from tvOS, Finesse doesn't qualify for the exemptions in App Store Connect's questionnaire. The answers are:

| Question | Answer |
|---|---|
| Does your app use encryption? | Yes |
| Does it qualify for any of the exemptions? | No |
| What type of encryption algorithms does it implement? | Standard encryption algorithms instead of, or in addition to, the encryption in Apple's operating system |
| Is it available on the App Store in France? | No |

Leaving France out means no French encryption declaration is needed, so there are no documents to upload. Making Finesse available in France would first need a declaration to ANSSI, which takes several weeks.

`asc_apply.py encryption --build <id>` records the same answers for an uploaded build by setting its encryption flag. Apple makes no declaration record for these answers, because no documents are needed. Don't add `ITSAppUsesNonExemptEncryption` set to `false` to `Info.plist`, because that would tell Apple the opposite. Once the first review is through, setting it to `true` stops App Store Connect asking again for every build.

## Version 1.0

Version 1.0 (build 20261109.0536) went to App Review with the website's export compliance answer set to "no non-exempt encryption", by the owner's choice. From the next build, `Info.plist` sets `ITSAppUsesNonExemptEncryption` to `true`, so every later build carries the answers above and App Store Connect doesn't ask. The API accepted `usesNonExemptEncryption` on the 1.0 build but didn't keep it, which is why the answer has to come from `Info.plist` or the website.

## US reporting

Nothing needs to be filed with the US Bureau of Industry and Security for Finesse, as far as we can tell. This isn't legal advice, so the owner should confirm it.

- The app is a mass-market item (5D992.c). Since BIS's encryption rule of March 2021, mass-market items no longer need the annual self-classification report.
- Finesse's own source is public and uses only standard, published algorithms through OpenSSL and Apple's frameworks. Publicly available encryption source code of that kind isn't subject to the Export Administration Regulations, and the same 2021 rule removed the email notice that used to be needed for it.
