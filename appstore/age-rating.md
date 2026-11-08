# Age rating

Finesse is rated 4+. The questionnaire rates what the app itself contains, and Finesse contains no media of its own. Everything it plays comes from the user's own Jellyfin server, which also enforces any parental limits set for each user. Media players like VLC and Infuse, and other Jellyfin clients, are rated the same way.

Every content question is answered None: violence of any kind, violent themes, guns or other weapons, sexual content or nudity, profanity or crude humour, mature or suggestive themes, horror or fear themes, alcohol, tobacco or drugs, simulated gambling, contests, and medical or treatment information.

Every capability question is answered No: unrestricted web access, user-generated content, messaging or chat, social media, advertising, gambling, loot boxes, health or wellness topics, parental controls and age assurance. Finesse has no browser, no way for users to post or share, and no parental controls of its own.

There is no manual override. `asc_apply.py` sends these answers using the API's field names.
