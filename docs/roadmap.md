# Implementation roadmap

[docs/spec.md](spec.md) says what the system is. This says what order to build it in, and
why that order.

**This document is revisable.** It is a plan, not a contract, and later milestones are
deliberately coarser than earlier ones — decomposing M8 in detail today would be inventing
precision that the work has not yet earned. Revise it as measurements come in.

Milestones map to GitHub milestones; the units inside them map to one issue ≈ one PR ≈ one
working session.

## What determined this order

**Dependency.** Some work cannot come second. The schema and migration framework precede
everything. The rules engine precedes the query layer, because §7 requires the sublibrary
predicate be first-class *from the first migration* — retrofitting it means revisiting
every query already written.

**The Xcode boundary.** [ADR 0008](adr/0008-core-first-swiftpm-package.md) splits the work.
M0–M5 need only the Command Line Tools. M6 onward need Xcode 26.x, App Sandbox, and
Instruments. **No unit of work straddles this line.**

**Risk.** Three assumptions are load-bearing and currently unproven: that byte-level
hashing hits the rescan target, that SFBAudioEngine round-trips tags correctly (§14 flags
WAV as poorly standardized and unverified), and that gapless playback survives the XPC
boundary. Each is scheduled as early as its dependencies allow, so that being wrong is
cheap.

**Priority order (§1).** UI polish is priority #1 but cannot be validated before there is a
library to render. M5 exists to resolve that tension: it proves the data design at full
scale before any UI work begins.

---

## Track D — Design (parallel, starts immediately)

**UI polish is priority #1, and it has almost no dependency on the milestone chain.**
Treating "UI" as one indivisible block that lands at M8 was wrong: it has three distinct
dependency profiles, and only the last of them belongs at M8.

| Stage | Needs | When |
|---|---|---|
| **D1** Design decisions | nothing | now |
| **D2** Prototype on synthetic data | Xcode only | as soon as Xcode is installed |
| **D3** Real-data views | M0, M1, M4 | parallel with M5 |
| **M8** Complete, polished app | D1–D3, M6, M7 | M8 |

### D1 — Design decisions (no Xcode)

Layout, grid density, artwork treatment, typography, spacing, states, and interaction flows,
settled in a design tool and recorded in `docs/design/`.

**Deliverable:** `docs/design/` — a component inventory, layout decisions with rationale,
the artwork and placeholder treatment, and the state matrix (empty, scanning, missing file,
no artwork, no search results).

**Exit criteria**
- Every view in §12 has a resolved layout: album grid, artist list and detail, genre list,
  album detail with disc groupings, search results, queue, now-playing bar
- The generated placeholder for albums without artwork is designed, not deferred (§11)
- Light and dark are both resolved
- States are designed, not discovered during implementation: empty library, scan in
  progress, missing files greyed, divergent tags flagged (§6)
- Thumb, medium, and full artwork sizes are chosen against real layouts, so §11's cache
  sizes are driven by the design rather than guessed

**D1 answers five open questions.** Ratings UI (§16.3), mini player (§16.6), keyboard
shortcuts (§16.7), sort defaults (§16.10), and first-run onboarding (§16.8) are design
questions, not engineering ones. Resolving them here removes them as blockers on M7 and M8
rather than leaving them to be defaulted into an implementation.

### D2 — Prototype on synthetic data (Xcode, no core dependency)

A throwaway SwiftUI target rendering ~50,000 fabricated albums with generated placeholder
images. No database, no scanner, no dependency on the core package. Real Swift, real
Previews, real scrolling.

**This is where the §12 grid decision gets settled.** The spec says to measure before
choosing between `LazyVGrid` and `NSCollectionView` — and that measurement depends on
render density and image decode cost, **not on whether the metadata is real.** It therefore
has no dependency on M0–M5 and should happen as early as Xcode allows. It is the cheapest
available test of priority #2, and it also answers whether SwiftUI can express the D1
design at all, which mockups cannot.

Lives in `Prototypes/`, tracked but explicitly non-shipping. It does not violate
[ADR 0008](adr/0008-core-first-swiftpm-package.md)'s no-UI-in-core rule, since it is not the
core package. Components are harvested into M8 rather than rewritten.

**Exit criteria**
- Album grid measured in Instruments at 50k scale; 60fps sustained, or `NSCollectionView`
  chosen on evidence
- The §12 grid decision is recorded as an ADR, with the numbers
- The D1 design is proven expressible in SwiftUI, or D1 is revised where it is not
- Thumb, medium, and full artwork sizes confirmed against real rendering

### D3 — Real-data views (needs M0, M1, M4)

Browse views over an actual library: schema, album grouping, and browse queries. **It needs
neither playback (M6) nor FSEvents scanning (M7)** — a library populated by the M5 generator
is enough — so it runs parallel with M5 rather than waiting for M7.

**Feeding M8.** M8 begins with the design settled, the grid decision made on measurement,
and components already proven against real data — not with a blank canvas.

---

## M0 — Foundations

Package skeleton, schema, migrations, model types.

**De-risks:** nothing. This is scaffolding, and it should be boring.

**Exit criteria**
- `swift test` runs green in a clean checkout
- The §5 schema is created entirely by a versioned migration, not by hand
- Model types round-trip through GRDB, including nullable and enum-backed columns
- The core package imports neither SwiftUI nor AppKit, enforced by a test or build setting

**Note:** §16 question 9 (shuffle as in-place reorder vs. play-order overlay) is **resolved**
— play-order overlay, per [ADR 0011](adr/0011-shuffle-as-a-play-order-overlay.md). Its schema
impact is `queue_items.shuffle_position` plus `shuffle_enabled` and `repeat_mode` on `queues`,
and it is carried by the initial migration rather than migrated for later. The feature itself
is still M9.

## M1 — Identity and grouping

Fixture library, `audio_hash` per format, duplicate collapse, album grouping.

**De-risks:** the central claim of [ADR 0004](adr/0004-metadata-first-identity-without-decoding.md)
— that identity can be computed from bytes alone, cheaply, without decoding.

**Exit criteria**
- The §17 fixture library exists, covering every named awkward case
- FLAC, MP3, and WAV hashing implemented, with the zeroed-STREAMINFO fallback
- **Two files differing only in tags produce the same `audio_hash`** — the spec's stated
  test assertion (§6), verified here against fixtures
- Bit-identical copies across two roots collapse to one track with N files
- `preferred_file_id` follows the documented preference order
- `album_key` groups a multi-root album as one album; compilations are detected

## M2 — Tag I/O

Read and write through SFBAudioEngine's `AudioFile`. No UI.

**De-risks:** the second unproven third-party integration. §14 explicitly flags WAV tagging
as poorly standardized, requiring a documented convention and verified round-trip.

**Exit criteria**
- Round-trip verified per format for every field in §14, non-ASCII included
- **The WAV tagging convention is chosen, documented, and verified against a fixture** —
  this is a decision that needs recording, likely as an ADR
- Writes are atomic (temp + `rename(2)`), never in place
- Preflight rejects the whole edit when any backing file is absent or unwritable
- No partial write is possible across copies, proven by a test that makes one file
  unwritable mid-set
- `audio_hash` is unchanged after a real write, closing the M1 assertion for good

## M3 — Rules engine and query layer

Rule compilation and the sublibrary predicate.

**De-risks:** the §7 requirement that no code path reads the library without the predicate.
Cheap now, expensive once query surfaces exist.

**Exit criteria**
- All seven operators and both `match` modes compile correctly
- Output is fully parameterized — a test asserts no rule value reaches SQL as literal text
- `path` predicates match **any** backing file, not only the preferred one
- The engine has no reference to sublibraries, collections, or any consumer
- Every query function in the layer accepts the predicate; a test or lint catches one that
  does not

## M4 — Search and browse queries

FTS5 and the queries behind Albums, Artists, Genres.

**Exit criteria**
- FTS5 index maintained on every write path that changes searchable text (the table is
  `content=''`, so nothing is automatic)
- Non-ASCII and diacritic-insensitive search verified
- Browse queries for each view, all predicate-aware
- Search is scoped to the active sublibrary by default, with global as an option (§13)

## M5 — Scan orchestration and the performance gate

Scan sequencing, incremental diffing, and full-scale measurement.

**This milestone is a go/no-go on the data design.** It is the last point at which changing
course is cheap.

**De-risks:** everything M0–M4 assumed.

**Exit criteria**
- Incremental scan re-reads a file only when `size` or `mtime` differs
- Missing files become `scan_state = 'missing'` and are retained, never deleted
- A **generated 50,000-track library** exists for measurement
- Measured against §15: full rescan under 5 minutes; search first results under 50ms;
  sublibrary switch under 100ms
- **Numbers are recorded in the repository**, not just observed. A missed target is a
  finding that gets addressed here, not deferred into the UI milestones

---

*Everything below requires Xcode 26.x. Decomposition is intentionally coarse — revise it
when M5 lands.*

## M6 — App shell and playback transport

Two-target Xcode project, App Sandbox from the start, the XPC protocol, and SFBAudioEngine
playback.

**De-risks:** the third unproven assumption — gapless playback across a process boundary.

**Exit criteria**
- App and XPC service targets build and codesign; sandbox on from the first commit
- The service holds at most one enqueued next track and owns no queue semantics
- **Gapless verified by listening**, not only by inspecting state — including MP3 encoder
  delay and padding
- Now Playing and media keys work, registered from the app process
- Killing the service mid-playback restarts it and resumes at the last reported position

**Blocked on §16:** ReplayGain (1), crossfade (2), output device selection (5).

## M7 — Roots, scanning, artwork

Security-scoped bookmarks, FSEvents, and the artwork pipeline.

**Exit criteria**
- Roots persist as bookmarks and survive restart under sandbox
- FSEvents produces an incremental update in under 1s
- Artwork extracted at scan time to a three-size on-disk cache, deduplicated by SHA-256
- Placeholders are generated from album title, never a generic icon
- Scanning never blocks the UI; progress is visible

**Blocked on §16:** first-run onboarding (8).

## M8 — Browse UI

Album grid, artist and genre views, album detail, search results, now-playing bar.

Begins from D1's settled design, D2's grid decision, and D3's components — not from scratch.

**Exit criteria**
- Grid holds 60fps sustained on the real 50k library, confirming D2's measurement against
  live data, artwork cache, and sublibrary predicate
- Search results use `NSTableView`; frame rate holds at tens of thousands of rows
- Sublibrary switching updates the full UI within 100ms
- Cold launch to interactive under 1s; idle memory under 400MB

**Blocked on §16:** ratings UI (3), mini player (6), keyboard shortcuts (7), sort defaults
(10) — all resolved by D1, so this milestone should start unblocked.

The `LazyVGrid` vs. `NSCollectionView` decision (§12) is made at D2, not here.

## M9 — Queues, collections, tag editing

**Exit criteria**
- Queue reorder is a single-row update; the renumbering fallback exists and is tested
- Switching the active queue does not stop playback
- Queues survive relaunch and restore without auto-playing
- Queues and collections are unaffected by the active sublibrary
- Tag editing UI over the M2 write path, single and batch, with divergence surfaced

**Blocked on §16:** playlist import (4). Shuffle and repeat semantics (9) are resolved —
see [ADR 0011](adr/0011-shuffle-as-a-play-order-overlay.md); the schema landed at M0 and
only the feature remains.

---

## Open questions gate real work

Nine of §16's eleven questions block a specific milestone, listed above. They are tracked
as issues so the answers get made and recorded rather than defaulted into an implementation.

**Answer them before the milestone they block**, not during it. Question 9 was the one that
had to be answered early regardless of when it ships — an overlay costs a column that an
in-place shuffle does not, and `queue_items` is created at M0. It is now resolved
([ADR 0011](adr/0011-shuffle-as-a-play-order-overlay.md)), leaving eight.

Five of them — 3, 6, 7, 8, and 10 — are design questions and are resolved by Track D as a
byproduct of work that has to happen anyway.
