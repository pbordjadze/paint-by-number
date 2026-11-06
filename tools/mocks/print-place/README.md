# Print placement mocks (throwaway, painting-company row 240)

Three places Print could live, drawn over CI's real iPhone 17 Pro screenshots of main at b49cc95
(`refs/ci-shots/main`: iphone-paint-progress, iphone-gallery, iphone-create-preview). They are
HTML overlays, not the app: the menus imitate iOS 26's.

- A: the painting's More menu gets Print Page….
- B: the gallery card's hold menu has Print… at its top level, not inside Share.
- C: a round Print button beside Start Painting on the New Painting preview.

Run: copy the three screenshots here, then `node shot.js` (Playwright, Chromium) writes
mock-a/b/c.png at 3x. `../contact_sheet.py out.png a.png b.png …` lays PNGs side by side.
