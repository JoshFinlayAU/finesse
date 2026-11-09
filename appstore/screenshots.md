# Screenshots

Apple TV screenshots are 1920x1080 or 3840x2160. Ours are 3840x2160, taken from the simulator by the demo-server UI test, so they only ever show the public demo's content. They aren't kept in the repository.

The listing uses eight, in this order:

1. `as-03-home`: Home, with the featured title and Continue Watching
2. `as-05-movies`: the Movies library with sort and filter
3. `as-08-detail`: a film's detail page
4. `as-10-bar`: the player's control bar over a film
5. `as-11-info`: the player's Info panel
6. `as-07-search`: Search with results
7. `as-02-user-picker`: choosing who's watching
8. `as-01-server-entry`: connecting to a server

To take a new set, run the demo-server test as described in `review-notes.md`, adding `TEST_RUNNER_DEMO_AVOID="<title>|<title>"` to keep titles off Home's featured spot when the test starts, and export the attachments from the result bundle. Check each picture before using it. The demo's library includes films that may still be under copyright and posters showing real actors, which are best kept out of the listing. The featured title changes by itself every few seconds, so check the Home shot in particular.
