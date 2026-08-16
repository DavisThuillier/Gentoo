# 0006. Build the rules engine as a standalone component with no sublibrary coupling

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §7

## Context

A **sublibrary** is a persistent global lens over the library, defined by metadata rules
and selected from a toolbar dropdown. When active it filters every browse view — Albums,
Artists, Genres — and, by default, search.

Smart collections are an explicit v1 non-goal (§2), but they are the same mechanism
pointed at a different table. Building the rules engine coupled to sublibraries would make
that later addition a rewrite rather than an extension.

## Decision

Implement rule evaluation as a standalone component that compiles a rule tree to a
parameterized SQL `WHERE` fragment. It has no knowledge of sublibraries, collections, or
any consuming feature.

**The sublibrary predicate is a first-class concept in the query layer from the first
migration.** Every library query function takes an optional predicate. There is no code
path that reads the library without going through it.

Rule values are **always** bound as parameters. Never string-interpolate a value into SQL.

`path` predicates match against **any** file backing the track, not only the preferred one.

Queues are independent of the active sublibrary: switching lenses never modifies, filters,
or clears a queue, and a queue may contain tracks the current lens would hide (§8).
Collections are likewise global, not sublibrary-scoped (§9).

## Consequences

- Smart collections become a small addition — point the same engine at a different table —
  rather than a refactor.
- The engine is unit-testable with no UI and no sublibrary context, which is a hard
  requirement (§17).
- Every new query function must thread the predicate through. This is easy to forget and
  produces a silent correctness bug: a view that ignores the active lens. It is the primary
  thing `db-guardian` exists to check.
- Parameterized compilation closes the injection surface that user-authored rules would
  otherwise open.
- Matching `path` against any backing file means the predicate cannot be a simple join on
  `preferred_file_id`; it needs an existence check across `files`.
- Queue independence means the queue view deliberately shows tracks that other views hide.
  This is correct behavior, not a bug.

## Alternatives considered

**Evaluating rules in Swift over fetched rows.** Simpler to write and to test. Rejected:
it requires fetching the unfiltered library before filtering it, which cannot meet the
100ms sublibrary-switch target on 50k tracks.

**Building the engine specifically for sublibraries, generalizing later.** Less
speculative. Rejected because the generalization is known to be needed — the spec names
smart collections as the follow-on — and retrofitting decoupling after consumers exist is
strictly more work than not coupling in the first place.

**String-interpolating rule values into SQL.** Rejected on injection grounds. User-authored
rule values are untrusted input.

**Making the sublibrary predicate implicit via a SQL view.** Would guarantee no query
bypasses it. Rejected because the lens changes at runtime, and rebuilding or reattaching a
view on every switch is worse than passing a predicate — and it would not compose with
FTS5 search.
