# 0007. Write tag edits to every backing file, atomically, or not at all

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §14

## Context

One logical track may be backed by N bit-identical files across watched roots
([0004](0004-metadata-first-identity-without-decoding.md)). Tag editing is the only path by
which this app writes user data, so it must be conservative.

If only the preferred file were written, the database and the remaining files on disk would
disagree, and a precedence rule would be needed to decide which wins on the next rescan.

All watched roots are assumed to be on always-available local storage (§2).

## Decision

A tag edit writes to **every** file backing the track, not just the preferred one.

**Preflight requirement.** Before applying any edit, verify every backing file is present
and writable. If any is not, refuse the edit entirely and tell the user which file is
unavailable. **Never perform a partial write across copies** — a half-applied edit
reintroduces exactly the divergence this design exists to prevent.

Write atomically per file: temp file, then `rename(2)`. Never edit in place.

Suppress the FSEvents-triggered rescan for files the app itself just wrote.

## Consequences

- After any successful edit, the database and every file on disk agree. No precedence rule
  is needed anywhere.
- Files remain the source of truth for tag data, so edits made in external tag editors are
  picked up on the next rescan for free.
- An edit costs N writes instead of 1. Acceptable: N is small, and roots are local storage.
- An unavailable copy blocks the edit entirely, which is a visible failure. This is
  deliberate — a loud refusal is better than a silent divergence.
- Atomic replacement means a crash mid-edit leaves the original file intact; the temp file
  is the only casualty.
- Without FSEvents suppression, every edit would trigger a redundant re-read of the files
  just written.
- **`audio_hash` must not change on a tag edit.** Assert this in tests
  ([0004](0004-metadata-first-identity-without-decoding.md)).

## Alternatives considered

**Write only the preferred file.** Cheapest. Rejected: it guarantees divergence between
copies and forces a precedence rule on every subsequent scan, permanently complicating the
data model to save a few writes.

**Write the database only, treating files as read-only.** Would make edits instant.
Rejected: it makes the database primary storage for tag data, which breaks its
rebuildability (§5) and means external tag editors and this app permanently disagree.

**Best-effort partial writes with a retry queue.** Would let edits proceed when a copy is
temporarily unavailable. Rejected as needless complexity given the local-storage assumption
in §2 — and a retry queue is a durable half-applied state, which is the thing being
avoided.

**Editing in place rather than temp-and-rename.** Faster for small tag changes. Rejected:
an interrupted in-place write can corrupt an audio file, and this is the only write path
to user data.
