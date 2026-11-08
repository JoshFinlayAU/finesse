# Custom licence agreement

**Status:** FINAL. The owner chose a custom licence agreement on 2026-11-09 and supplied the contact details and governing law the same day.

**Where it goes:** App Store Connect, under App Information, then License Agreement. It's plain text, so paste everything between the two lines below. `asc-api.md` sends the same text through the API. It applies in every territory where the app is sold, which is all of them except France.

**How it was written:** against Apple's "Instructions for Minimum Terms of Developer's End-User License Agreement", https://www.apple.com/legal/macapps/minterms/, read on 2026-11-09. That page sets 10 terms, and each section below notes which one it covers.

**The tension, also in `risks.md`:**

- **Apple's term 1:** an agreement may not give usage rules less restrictive than the App Store's.
- **The LGPL:** it gives rights over the source and the libraries that Apple's rules don't.
- **How this text handles it:**
  - The App Store copy is licensed on Apple's terms.
  - The source code and components are licensed separately, under their own licences.
  - Nothing here takes away the rights those licences give.

  This is the usual approach of open-source apps on the App Store. A lawyer should read it before release, and Apple may still question it.

---

FINESSE LICENCE AGREEMENT

Last updated: [date of publishing]

This agreement is between you and Athena Networks ("we", "us"), and covers the Finesse app for Apple TV ("the app") as you get it from the App Store.

1. Who this agreement is with

This agreement is between you and us only, not Apple. We, not Apple, are solely responsible for the app and its content. [Apple term 1]

2. Your licence to use the app

We give you a non-transferable licence to use the app on any Apple-branded products that you own or control, as allowed by the Usage Rules in the Apple Media Services Terms and Conditions. The app may also be used by other accounts associated with you through Family Sharing or volume purchasing, as those rules allow. [Apple term 2]

3. Open-source licences

Finesse is open-source software. Its source code is available at https://github.com/JoshFinlayAU/finesse under the GNU Lesser General Public License, version 3. The app also contains components under their own licences, including FFmpeg and mpv under the GNU Lesser General Public License, and OpenSSL under the Apache License 2.0. The full list, with each licence's text, is in the app under Settings, then Licences, and in the repository.

Those licences govern your rights to the source code and to each of those components. Nothing in this agreement limits or takes away any right those licences give you, including the right to obtain the source code, modify it, and build and use your own copy of the app with modified components. Where this agreement and one of those licences differ about a component, that licence applies to that component.

4. Support

We are solely responsible for any maintenance and support of the app, as described here or as required by law. Apple has no obligation to provide any maintenance or support for the app. Support is through https://github.com/JoshFinlayAU/finesse/issues and the contact details in section 9. [Apple term 3]

5. Warranty

The app is provided free of charge and, to the extent the law allows, without any warranty. Where a warranty can't be excluded under the law that applies to you, we, not Apple, are responsible for it. If the app fails to conform to any warranty that applies, you may notify Apple, and Apple will refund the purchase price, if any, that you paid for the app. To the maximum extent the law allows, Apple has no other warranty obligation for the app, and any other claims, losses, liabilities, damages, costs or expenses from a failure to conform to a warranty are our responsibility. [Apple term 4]

Nothing in this agreement excludes or limits rights you have under consumer law, including the Australian Consumer Law, that can't be excluded or limited.

6. Claims about the app

We, not Apple, are responsible for dealing with any claims by you or anyone else about the app or your possession or use of it. That includes product liability claims, claims that the app doesn't meet a legal or regulatory requirement, and claims under consumer protection or similar laws. This agreement does not limit our liability to you beyond what the law allows. [Apple term 5]

7. Intellectual property claims

If anyone claims that the app, or your possession or use of it, infringes their intellectual property rights, we, not Apple, are solely responsible for investigating, defending, settling and discharging that claim. [Apple term 6]

8. Your server, your content and other terms

The app plays media from a Jellyfin server that you run or that someone gives you access to. The app does not include any films, shows or other media. You are responsible for having the right to play what is on that server, and you must follow the terms of any server, service or other third party you use with the app. [Apple term 9]

9. Contact

Athena Networks
Parcel Locker 10303 80643
139 Brisbane Road
Booval QLD 4304
Australia
Phone: 1300 409 252 (from within Australia)
Email: support@athenanetworks.com.au
Issues: https://github.com/JoshFinlayAU/finesse/issues

Questions, complaints or claims about the app should be sent to these contact details. [Apple term 8]

10. Export and sanctions

You confirm that you are not located in a country that is subject to a US Government embargo, or that the US Government has designated as a "terrorist supporting" country, and that you are not listed on any US Government list of prohibited or restricted parties. [Apple term 7]

11. Apple as a third-party beneficiary

You and we agree that Apple and Apple's subsidiaries are third-party beneficiaries of this agreement. Once you accept this agreement, Apple has the right, and is taken to have accepted the right, to enforce it against you as a third-party beneficiary. [Apple term 10]

12. Changes and law

We may update this agreement with a new version of the app, and the date above will change. This agreement is governed by the laws of Queensland, Australia, except where the law that applies to you says otherwise.

---

**Before pasting:**

- **Bracketed notes:** remove "[Apple term N]". `asc_apply.py` strips them itself.
- **Apple's limit:** check the text against App Store Connect's current length limit. It's about 6,000 characters including the notes, and should be well within it.
- **Governing law:** Queensland, chosen by the owner. Apple's terms don't require the clause.
