# 0005. Store the library in SQLite via GRDB, with FTS5 for search

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §5, §13, §17

## Context

The library holds 10,000–50,000 tracks and must support: cold launch to interactive in
under 1s, first search results in under 50ms, and a full sublibrary switch with UI update
in under 100ms (§15).

Search is incremental typeahead across title, artist, album artist, album, and genre.
Sublibraries inject a `WHERE` clause into every library query
([0006](0006-rules-engine-as-standalone-component.md)), so the query layer must be
composable.

## Decision

SQLite through GRDB, with an FTS5 virtual table (`unicode61 remove_diacritics 2`) over the
searchable text columns. Migrations are versioned from the first commit that creates a
schema.

**The database is a rebuildable cache for tag data** — files on disk remain the source of
truth for every tag field. Ratings, play counts, collections, queues, and sublibraries
exist *only* in the database and are the data that genuinely needs a backup story.

Artwork is never stored as blobs in the database; only paths into the on-disk cache (§11).

Queue and collection `position` columns use integers with gaps (increments of 1024) so
that a reorder is a single-row update rather than a renumbering of the whole list.

## Consequences

- FTS5 makes the sub-50ms search target reachable on 50k rows.
- `remove_diacritics 2` means non-ASCII tags search naturally without the user
  transliterating.
- **Every schema change requires a versioned migration in the same commit.** The schema
  will change; there is no window during which "add the migration later" is acceptable.
- The tag half of the database can be rebuilt from disk at any time, so corruption there is
  recoverable by rescanning. The user-data half cannot, which is why §16 lists backup and
  export as an open question.
- Position-with-gaps eventually exhausts the gap on repeated insertions between the same
  pair of items. A renumbering path is needed as a fallback, just not on the common path.
- GRDB's Swift ergonomics keep query construction type-safe, which matters because the
  sublibrary predicate must compose with every query in the app.

## Alternatives considered

**Core Data / SwiftData.** First-party and well integrated with SwiftUI. Rejected: less
direct control over query plans and indexing at the scale required, no equivalent to FTS5's
performance for incremental typeahead, and awkward composition of a dynamic predicate into
every fetch.

**Raw SQLite via the C API.** Maximum control, no dependency. Rejected as needless work
against priority #3 — GRDB is a thin, mature layer that adds Swift type safety without
hiding SQL.

**`LIKE '%term%'` instead of FTS5.** No virtual table to maintain. Rejected: a leading
wildcard cannot use an index, so this degrades linearly and misses the 50ms target well
before 50k tracks.

**Storing artwork as database blobs.** Would simplify the cache story. Rejected: it bloats
the database, defeats its rebuildability, and puts image data on the query path — the most
likely cause of a janky grid (§11).
