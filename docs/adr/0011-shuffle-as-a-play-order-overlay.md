# 0011. Shuffle as a play-order overlay, not an in-place reorder

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §8, §16 (question 9)

## Context

Spec §16 question 9 asked whether shuffle reorders the queue in place or applies a
play-order overlay. It is not implemented until M9, but it is the one open question that
can cost a migration: `queue_items` is created by the initial migration in M0, and an
overlay needs a column that an in-place shuffle does not. `docs/roadmap.md` therefore
schedules the *answer* at M0 rather than the feature.

Three constraints bear on it.

**Priority #1 is UI polish (§1), in an album-centric player.** §12 makes the album grid the
default view and refuses a top-level flat track list. An album's track order is authored
data, not incidental — the sequence is part of the record. An in-place shuffle destroys it
on a button press, and toggling shuffle back off cannot restore what was overwritten.

**§8 requires reorder be a single-row update.** `position` uses gaps of 1024 specifically
so that dragging one item does not renumber the queue. An in-place shuffle of a
10,000-item queue rewrites 10,000 rows, which is the operation that design exists to avoid.

**§8's "play next" inserts immediately after the currently playing item.** With one order
this is unambiguous. With a shuffle that has overwritten the authored order, "after the
current item" has already lost the distinction between where the user sees the item and
where it will play.

## Decision

Shuffle is a **play-order overlay**. `queue_items.position` is the authored order and is
never mutated by shuffling. A nullable `queue_items.shuffle_position` holds the shuffled
order, and playback follows it while the queue's `shuffle_enabled` is set.

Shuffle and repeat are **per-queue state, persisted in the database** — `shuffle_enabled`
and `repeat_mode` are columns on `queues`, not a global application preference. §8 already
requires that queues persist across launches and that switching the active queue disturbs
nothing else; making these queue properties means a restored queue comes back exactly as
the user left it, shuffled order included.

Semantics are specified in §8.

## Consequences

- Toggling shuffle off restores the authored order exactly, because it was never lost.
- Enabling or disabling shuffle is not a reorder, so it does not interact with the §8
  gap-numbering scheme or rewrite the queue.
- `shuffle_position` uses the same gaps-of-1024 convention as `position`, so inserting into
  the shuffled order stays a single-row update too.
- Queue rendering now has two orders to keep straight. Every read of a queue must decide
  which it wants, and "the queue" becomes an ambiguous phrase in code review. The UI has to
  answer a question that does not arise with one order: whether the queue view lists
  authored or play order while shuffled. That is a real cost, and it is paid in M9.
- The shuffled order is durable rather than regenerated per session, which is what makes
  restore exact — but it also means a stale `shuffle_position` is now a state that can be
  wrong. Items added while shuffled must be assigned one.
- A unique index on `(queue_id, shuffle_position)` is needed to keep the overlay total and
  collision-free. SQLite treats NULLs as distinct in a unique index, so the not-shuffled
  case needs no special handling.
- This commits M9 to implementing two orderings rather than one. It is a larger feature
  than in-place shuffle would have been.

## Alternatives considered

**Shuffle the queue in place.** Rewrite `position` on shuffle. Genuinely simpler: one
order, so the list you see is the order that plays, nothing hidden, and no second column to
keep consistent. Rejected on priority #1 — destroying an album's authored order on a toggle,
irreversibly, is the kind of detail that makes an app feel careless — and on §8's
single-row-update requirement, which a full renumber violates outright.

**Overlay computed in memory, not persisted.** Same semantics, no `shuffle_position`
column: generate the shuffled order at play time and hold it in the app. Cheaper schema,
and the app owns queue semantics anyway (§3). Rejected because §8 requires queues restore
across launches; an in-memory order means relaunching silently reshuffles, so the queue does
not come back as the user left it.

**Global shuffle and repeat state outside the database.** One app-wide setting in
`UserDefaults`, applying to whichever queue is active. This is how most players behave, and
it costs no schema at all. Rejected because §8 treats named queues as independent objects
that persist and switch without side effects; a global toggle means switching queues silently
changes how the previous one would have played, and the state no longer survives with the
thing it describes.

**Defer the decision and land the overlay's columns unused.** The overlay's schema is a
superset of the in-place schema, so shipping it while leaving §16 question 9 open would
remove the migration risk without deciding anything. Rejected because it decides the schema
either way while pretending not to, and CONTRIBUTING requires open questions be answered in
the spec before they are implemented rather than defaulted into one.
