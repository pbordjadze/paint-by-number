# W6 — Gallery search and favorites (Sonnet 5.5) — report

Branch `wt/w6-gallery`, head `017a52a`. Uncompiled here; strings_check ok (274/274), self-test passed.

## Changed
- `Artwork.isFavorite` (`decodeIfPresent` in both decode branches, no format bump).
  `Library.setFavorite` guarded like rename (incl. `needsNewerApp`), via `persistMeta`, so
  write failures surface the Retry toast. `inProgress`/`finished` list favorites first (stable
  partition); `inProgress(matching:)` / `finished(matching:)` apply the query.
- `Model/GalleryQuery.swift`: `GalleryFilter` (String raw, `@SceneStorage`), `GalleryQuery`
  (filter + search; `includes`, `isActive`, `isSearching`), `TitleSearch` (pure, nonisolated;
  every query word must prefix a title word; case/diacritic/width-insensitive; punctuation
  separates; blank matches all).
- `AppShellView`: `@SceneStorage("galleryFilter")`, `.searchable(prompt: "Search paintings")`,
  trailing Show menu (inline picker All/Favorites; disabled while the library is empty);
  subtitle counts the visible set (placeholders only when nothing is narrowed).
- `GalleryView`: takes the query; animates on visible ids; empty states
  `ContentUnavailableView.search(text:)` and "No Favorites" + one line. Context menu starts with
  Favorite/Unfavorite (`heart`/`heart.slash`) + divider. `ArtworkCard`: `heart.fill` glass badge
  top-leading.
- Demo: `gallery` has one favorite (Lighthouse); new `gallery-favorites`, `gallery-search`
  (query "re" → Red Barn, Regatta), their `-dark` variants and `gallery-no-favorites-long-text`.
- Tests: LibraryTests (persistence, old meta, ordering, query lists, write-failure retry,
  newer-app ignored), GalleryQueryTests (matcher, filter+search), GalleryActionsTests (menu,
  badge, move, Show filter + empty state, search + empty state), LongTextTests.
- CLAUDE.md: one bullet before "Save failures".

## Deviations
- Favorite status is in the card's accessibility *value* ("Favorite, 42 percent painted"),
  the label stays the title (UI tests and VoiceOver users find cards by title).
- Duplicating a favorite keeps the mark.

## Open
- UI test queries for the Show menu / search field are best guesses for iOS 26 (helpers
  `chooseShow` and search in GalleryActionsTests).
- `.searchable` stays visible with an empty library.
