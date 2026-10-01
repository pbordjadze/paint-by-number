# W6 — Gallery search and favorites

Model: Sonnet 5.5.

## Goal

Find a painting by name, and mark paintings as favorites that show first and can be viewed
on their own. Small, native, iPad-first.

## Today (wave 1)

- `GalleryView` shows two fixed sections, "In Progress" (newest `modifiedAt` first) and
  "Finished" (`completedAt`), as an adaptive grid of `ArtworkCard`s; a context menu holds
  Rename, Duplicate, Share…, Print, Save to Photos, Restart, Delete (undoable, confirmed).
  `Library.inProgress` / `Library.finished` are computed from `artworks`.
- `Artwork` (`meta.json`) decodes tolerantly with `decodeIfPresent`; `currentFormat` is 2.
- No search, filter, sort, favorites or multi-select.

## Design

- `Artwork.isFavorite: Bool` (default false; `decodeIfPresent`; no format bump).
  `Library.setFavorite(_ id:, _ favorite: Bool)` persists through the existing per-artwork
  write queue; `ArtworkCard` shows a small heart badge (SF `heart.fill`, accent tint) at the
  top-leading corner when favorite, with an accessibility label "Favorite".
- Context menu gains "Favorite" / "Unfavorite" (first item, `heart` / `heart.slash`). On
  iPad with a pointer, a hover-revealed heart button on the card is **not** added (keep one
  path; the menu is reachable by right-click and long press).
- Ordering: within each section, favorites come first, then the existing order. Toggling a
  favorite animates the card's move (the grid already animates reorders on rename).
- Filter: a toolbar menu "Show" with All (default) and Favorites. With Favorites on, both
  sections show only favorites; if none, `ContentUnavailableView("No Favorites", systemImage:
  "heart")` with a line explaining the context-menu action. The filter is `@SceneStorage`.
- Search: `.searchable(text:)` on the gallery's navigation stack, placement automatic
  (iPad toolbar, iPhone navigation bar), prompt "Search paintings". Matches the title on
  word prefixes, case- and diacritic-insensitive ("ba" finds "Red Barn"; "arn" does not).
  Empty result → `ContentUnavailableView.search(text:)`. Search applies on top of the
  filter.
- Counts in the navigation subtitle reflect the visible set.
- Demo data: the `gallery` scenario gets one favorite among its paintings so the badge is
  screenshotted; new scenarios `gallery-favorites` (filter on) and `gallery-search` (a query
  typed, two results).

## Tests

- `LibraryTests`: favorite toggles persist across a reload; an old `meta.json` without the
  field decodes as not favorite; favorites order first within a section.
- `GalleryActionsTests` (UI): Favorite via the context menu shows the badge and moves the
  card first; the Show menu filters; search narrows to the matching card and the empty state
  appears for a nonsense query; VoiceOver labels of the badge and the heart menu item.
- Long-text scenario: `gallery-long-text` already exists; make sure the Show menu label and
  the empty states scale.

## Strings

"Favorite", "Unfavorite", "Favorite" (badge label), "Show", "All", "Favorites", "No
Favorites", its description, "Search paintings". Plurals for counts already exist.

## CLAUDE.md

One line under Library: `isFavorite`, the Show filter (`@SceneStorage`), search semantics.

## Acceptance

- Screenshots of `gallery`, `gallery-favorites`, `gallery-search` on iPad and iPhone, light
  and dark, look native; the tests above pass.

## Risks

- `Artwork` is also edited by W1c (two new fields). Both edits are additive `decodeIfPresent`
  fields; the orchestrator merges W6 first and W1c rebases its edit on it (no history
  rewrite: W1c simply edits on top after the merge).
