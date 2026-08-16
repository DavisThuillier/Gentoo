# Desktop Music Player — Implementation Spec

**Target:** macOS only
**Status:** Draft v0.2 — architecture and dependencies settled; product surface partially open (see §16)

**Changes from v0.1:** SFBAudioEngine adopted for both tag I/O and playback, replacing
AVAudioEngine. Identity hashing corrected — no longer requires decoding. Tag write scope
resolved. `user_edited_fields` removed.

---

## 1. Overview

A native macOS music player built on a client–server split. The GUI client owns the
library, browsing, queues, and collections. A separate playback service owns decode
and audio output. The client never touches an audio buffer; the service never knows
what a collection is.

**Formats:** MP3, FLAC, WAV.
**Library scale:** 10,000–50,000 tracks.
**Distribution:** personal install initially; possible public distribution later.

### Priority order (drives every tradeoff below)

1. UI polish
2. Large-library performance
3. Smallest shippable v1
4. Playback fidelity

This ordering is deliberate and load-bearing. Where a choice trades fidelity for
simplicity or polish, take it.

---

## 2. Non-goals for v1

- Network/remote control. The service is local-only, single-machine.
- Streaming audio to other devices.
- Smart/rule-based collections (the rules engine ships in v1 for sublibraries — see §7 —
  so this becomes a thin addition later).
- Bit-perfect output, hog mode, integer mode, manual sample-rate switching.
- Formats beyond MP3/FLAC/WAV.
- Cross-format duplicate detection (FLAC and MP3 of the same song are separate tracks — see §6).
- Library sync, cloud, or mobile companion.
- Playing while the GUI is closed.
- Support for music on external or network volumes. All watched roots are assumed to be
  on always-available local storage.

---

## 3. Architecture

### Process model

```
┌──────────────────────────────────────┐
│  MusicPlayer.app  (SwiftUI/AppKit)   │
│                                      │
│  • SQLite library (GRDB)             │
│  • Scanner (FSEvents)                │
│  • Queues, collections, sublibraries │
│  • Artwork cache                     │
│  • Tag writing (SFBAudioEngine)      │
│  • MPNowPlayingInfoCenter            │
│  • MPRemoteCommandCenter             │
└───────────────┬──────────────────────┘
                │ NSXPCConnection
┌───────────────┴──────────────────────┐
│  PlaybackService.xpc                 │
│                                      │
│  • SFBAudioEngine AudioPlayer        │
│  • Decode, transport, seek, volume   │
│  • Gapless via enqueued next decoder │
└──────────────────────────────────────┘
```

The XPC service is bundled inside the app (`Contents/XPCServices/`), with
`ServiceType: Application` in its `Info.plist`. It terminates when the app does.
Playback is not expected to survive quitting the GUI, so a launchd `LaunchAgent`
would be unnecessary complexity.

**Why split at all, given it dies with the app:** crash isolation. This matters *more*
now that third-party decoders sit in the audio path — a malformed file that kills the
decoder must not take the window with it. The app detects XPC interruption, restarts
the service, and resumes at the last reported position.

### Critical constraint: Now Playing lives in the app process

`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` do not work correctly from an XPC
service. Media keys, the Control Center widget, and the Now Playing display must be
registered by the app process. The app mirrors engine state upward and publishes it.

### The service is a transport, not a queue manager

SFBAudioEngine's `AudioPlayer` maintains its own internal decoder queue. **Do not use it
as the app's queue.** The service holds at most the currently playing track plus one
enqueued next track for gapless. All queue logic — ordering, advancing, shuffle, repeat,
switching active queues — lives in the app. The service never reads the library database.

---

## 4. Technology choices

| Concern | Choice | Rationale |
|---|---|---|
| Language | Swift, throughout | One toolchain, one project |
| GUI | SwiftUI, with AppKit where needed | See §12 for where AppKit is mandatory |
| Audio | SFBAudioEngine `AudioPlayer` | Own FLAC/MP3 decoders with correct gapless, incl. MP3 encoder delay/padding |
| Tag I/O | SFBAudioEngine `AudioFile` | Same dependency, native Swift API, read + write |
| IPC | NSXPCConnection | First-party, typed, no hand-rolled protocol |
| Database | SQLite via GRDB | Mature, fast, good Swift ergonomics, FTS5 |

### On the SFBAudioEngine decision

v0.1 specified AVAudioEngine on the rationale of "first-party frameworks only, nothing to
vendor or license-audit." Once SFBAudioEngine is a dependency for tag writing — and it must
be, since **AVFoundation cannot write metadata at all** — that rationale is spent. Using it
for playback as well costs nothing additional and removes the MP3 gapless compromise that
v0.1 accepted as a known limitation.

It installs via SPM and builds from source, so codesigning remains straightforward.

**Licensing task before any public distribution:** SFBAudioEngine's own license is permissive,
but it vendors third-party decoders and TagLib, each with their own terms. TagLib is settled —
its dual LGPL/MPL licensing permits static linking into a closed application, with copyleft
scoped to modifications of TagLib's own files. The decoder dependencies need individual audit;
any that are LGPL-only require dynamic linking or shipping relinkable objects. This is a
compliance checklist, not a blocker, but do it before shipping rather than after.

### Rejected alternatives (recorded so they aren't relitigated)

- **MPD as the server.** Supports only one `music_directory`, cannot do multiple watched roots
  without a symlink farm. Tags are read-only. Single server-side queue. Path-tree data model
  conflicts with metadata-first indexing. GPL-2.0 complicates later distribution.
- **libmpv.** LGPL-buildable, but carries a video player's surface area for three audio codecs
  and provides no library layer.
- **Rust + Symphonia.** Better decode control and real-time safety, but that buys fidelity,
  which is priority #4. Costs an FFI boundary, a hand-rolled IPC protocol, a second toolchain.
- **Tauri/web UI.** Trades native menu bar, keyboard handling, Finder integration, and Now
  Playing for iteration speed that isn't a stated goal.
- **AVFoundation for tag writing.** Reads fine; has no write path short of re-encoding, which
  is unacceptable for lossless files. Do not propose this again.
- **Hand-rolled tag parsing.** Weeks of work plus a long edge-case tail on real-world malformed
  tags, against priority #3.

---

## 5. Data model

Metadata-first. **File paths are not identity.** Files move between watched roots; the same
file may exist in multiple roots; folder structure is explicitly irregular and carries no meaning.

```sql
CREATE TABLE roots (
  id                 INTEGER PRIMARY KEY,
  path               TEXT NOT NULL UNIQUE,
  bookmark           BLOB,            -- security-scoped bookmark, survives restarts
  enabled            INTEGER NOT NULL DEFAULT 1,
  last_full_scan_at  INTEGER
);

CREATE TABLE files (
  id            INTEGER PRIMARY KEY,
  root_id       INTEGER NOT NULL REFERENCES roots(id) ON DELETE CASCADE,
  track_id      INTEGER REFERENCES tracks(id),
  path          TEXT NOT NULL UNIQUE,
  size          INTEGER NOT NULL,
  mtime         INTEGER NOT NULL,
  format        TEXT NOT NULL,        -- mp3 | flac | wav
  audio_hash    TEXT,                 -- identity key, see §6
  sample_rate   INTEGER,
  channels      INTEGER,
  bit_depth     INTEGER,
  bitrate       INTEGER,
  duration_ms   INTEGER,
  scan_state    TEXT NOT NULL,        -- ok | missing | error
  scan_error    TEXT,
  last_seen_at  INTEGER NOT NULL
);
CREATE INDEX idx_files_track ON files(track_id);
CREATE INDEX idx_files_hash  ON files(audio_hash);

CREATE TABLE tracks (
  id                     INTEGER PRIMARY KEY,
  audio_hash             TEXT NOT NULL UNIQUE,
  preferred_file_id      INTEGER REFERENCES files(id),
  album_id               INTEGER REFERENCES albums(id),
  title                  TEXT,
  artist                 TEXT,
  artist_sort            TEXT,
  album_artist           TEXT,
  track_no               INTEGER,
  disc_no                INTEGER,
  year                   INTEGER,
  genre                  TEXT,
  duration_ms            INTEGER,
  musicbrainz_track_id   TEXT,
  added_at               INTEGER NOT NULL,
  play_count             INTEGER NOT NULL DEFAULT 0,
  last_played_at         INTEGER,
  rating                 INTEGER          -- nullable, 0–5
);
CREATE INDEX idx_tracks_album ON tracks(album_id);

CREATE TABLE albums (
  id                       INTEGER PRIMARY KEY,
  album_key                TEXT NOT NULL UNIQUE,  -- see §6
  title                    TEXT,
  album_artist             TEXT,
  album_artist_sort        TEXT,
  year                     INTEGER,
  disc_count               INTEGER,
  is_compilation           INTEGER NOT NULL DEFAULT 0,
  artwork_id               INTEGER REFERENCES artwork(id),
  musicbrainz_release_id   TEXT
);

CREATE TABLE artists (
  id          INTEGER PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  sort_name   TEXT
);

CREATE TABLE artwork (
  id            INTEGER PRIMARY KEY,
  sha256        TEXT NOT NULL UNIQUE,
  source        TEXT NOT NULL,   -- embedded | sidecar
  width         INTEGER,
  height        INTEGER,
  path_thumb    TEXT,            -- on-disk cache, see §11
  path_medium   TEXT,
  path_full     TEXT
);

CREATE TABLE sublibraries (
  id          INTEGER PRIMARY KEY,
  name        TEXT NOT NULL,
  rule_json   TEXT NOT NULL,     -- see §7
  position    INTEGER NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE collections (
  id          INTEGER PRIMARY KEY,
  name        TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE collection_items (
  collection_id  INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  track_id       INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  position       INTEGER NOT NULL,
  PRIMARY KEY (collection_id, position)
);

CREATE TABLE queues (
  id                INTEGER PRIMARY KEY,
  name              TEXT NOT NULL,
  is_active         INTEGER NOT NULL DEFAULT 0,
  shuffle_enabled   INTEGER NOT NULL DEFAULT 0,
  repeat_mode       TEXT NOT NULL DEFAULT 'off',  -- off | all | one
  created_at        INTEGER NOT NULL
);

CREATE TABLE queue_items (
  queue_id          INTEGER NOT NULL REFERENCES queues(id) ON DELETE CASCADE,
  track_id          INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  position          INTEGER NOT NULL,   -- authored order, never mutated by shuffle
  shuffle_position  INTEGER,            -- play order when shuffled, see §8
  PRIMARY KEY (queue_id, position)
);
-- NULLs are distinct in a SQLite unique index, so this constrains the shuffled
-- order without needing a partial index for the unshuffled case.
CREATE UNIQUE INDEX idx_queue_items_shuffle ON queue_items(queue_id, shuffle_position);

CREATE TABLE play_history (
  id         INTEGER PRIMARY KEY,
  track_id   INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  played_at  INTEGER NOT NULL,
  ms_played  INTEGER NOT NULL,
  completed  INTEGER NOT NULL
);

CREATE VIRTUAL TABLE tracks_fts USING fts5(
  title, artist, album_artist, album, genre,
  content='', tokenize='unicode61 remove_diacritics 2'
);
```

`files` → `tracks` is many-to-one: one logical track, N bit-identical copies on disk.

**The database is a rebuildable cache, not primary storage** — for tag data. Files on disk
remain the source of truth for all tag fields (§14). Ratings, play counts, collections, queues,
and sublibraries exist only in the database and do need a backup story eventually.

---

## 6. Scanning and identity

### Watched roots

The user configures N watched folders in arbitrary locations. Structure inside them is
irregular and carries no meaning — everything is derived from tags.

Roots are stored as **security-scoped bookmarks**, not paths, so access survives restarts
under App Sandbox.

### Triggers

- **FSEvents** stream per root, for live incremental updates.
- **Manual full rescan**, user-initiated, ignores mtime and re-reads everything.

A file is re-read on incremental scan if `size` or `mtime` differs from the stored row.

### Track identity — no decoding

`audio_hash` identifies the audio stream independent of metadata, so tag edits never change
identity. **Computed from bytes only. Never decode to hash** — decoding 50k files would take
hours and blow the §15 rescan target.

| Format | Source of hash |
|---|---|
| FLAC | The MD5 of unencoded audio already stored in the STREAMINFO block — zero cost. If absent or all-zero (some encoders omit it), fall back to hashing frame bytes. |
| MP3 | SHA-256 over MPEG frame bytes with ID3v1, ID3v2, and APE regions excluded. |
| WAV | SHA-256 over the contents of the `data` chunk. |

For MP3 and WAV, bound the I/O: hash the first 1MB and last 1MB of audio bytes plus the total
audio byte length. This is sufficient for detecting bit-identical duplicates and avoids reading
hundreds of gigabytes on a full rescan.

**Test assertion:** editing any tag field must leave `audio_hash` unchanged. If it doesn't,
the implementation is wrong.

### Duplicate handling

Files sharing an `audio_hash` collapse into one `tracks` row with N `files` rows behind it.
The library shows one entry. `preferred_file_id` selects which copy plays.

This catches **bit-identical copies only** — the same encode in two watched roots. A FLAC and
an MP3 of the same song hash differently and remain separate tracks. Cross-format duplicate
detection is out of scope (§2).

Default preference order: highest bit depth → highest sample rate → lossless over lossy →
first-configured root. The user can override per-track.

**If copies carry divergent tags at scan time,** the preferred file's tags populate the `tracks`
row. Flag the divergence in the UI and offer to sync (§14).

### Album grouping

`album_key` = normalized, lowercased, whitespace-collapsed
`(album_artist ?? artist) + album_title + year`.

Explicitly **not** path-derived. An album split across two watched roots is one album. Where
`album_artist` is absent and track artists differ, mark `is_compilation` and group under a
compilation identity rather than fragmenting into per-artist albums.

### Missing files

Files that vanish are marked `scan_state = 'missing'` and retained, not deleted. Tracks whose
files are all missing stay in the library, greyed, and are skipped on playback. This preserves
play counts, ratings, and collection membership.

---

## 7. Sublibraries and the rules engine

A **sublibrary** is a persistent global lens over the library, defined by metadata rules and
selected from a dropdown. When active, it filters every browse view — Albums, Artists, Genres —
and, by default, search.

**This is a `WHERE` clause injected into every library query.** It must be a first-class concept
in the query layer from the first migration. Every query function takes an optional sublibrary
predicate. There is no code path that reads the library without going through it.

### Rule format

```json
{
  "match": "all",
  "rules": [
    { "field": "genre", "op": "equals",   "value": "Jazz" },
    { "field": "path",  "op": "contains", "value": "/Vinyl Rips/" },
    { "field": "year",  "op": "gte",      "value": 1960 }
  ]
}
```

- `match`: `all` | `any`
- `field`: `genre` | `artist` | `album_artist` | `album` | `year` | `path` | `format` |
  `bit_depth` | `sample_rate` | `added_at` | `rating`
- `op`: `equals` | `not_equals` | `contains` | `not_contains` | `starts_with` | `gte` | `lte` | `between`

Rules compile to a parameterized SQL `WHERE` fragment. Never string-interpolate values.

`path` predicates match against **any** file backing the track, not just the preferred one.

### Relationship to smart collections

The rules engine is v1 because sublibraries require it. Smart collections are the same engine
pointed at a different table and should be a small later addition, not a rewrite. Build the
engine as a standalone component with no sublibrary-specific coupling.

---

## 8. Queues

There is always exactly one **active queue**. The user can create additional named queues and
switch which is active. Switching the active queue does not stop playback of the current track.

Operations:
- Drag to reorder within a queue
- **Play next** — insert immediately after the currently playing item
- **Add to end**
- Remove item, clear queue
- Create, rename, delete, duplicate a queue

**Queues are independent of the active sublibrary.** Switching lenses never modifies, filters,
or clears a queue. A queue may contain tracks the current lens would hide.

Queues persist across launches. On launch, restore the active queue and the last playback
position without auto-playing.

`position` is an integer with gaps (increments of 1024) so reorders are single-row updates
rather than renumbering the whole queue.

### Shuffle and repeat

**Shuffle is a play-order overlay, not a reorder.** `position` is the authored order and is
never mutated by shuffling. `shuffle_position` carries the shuffled order, using the same
gaps-of-1024 convention so insertions into it are also single-row updates. See
[ADR 0011](adr/0011-shuffle-as-a-play-order-overlay.md).

Shuffle and repeat are **per-queue state**, stored on the `queues` row and persisted with
it. Each named queue remembers its own; switching the active queue does not carry them over.

- **Enabling shuffle** assigns `shuffle_position` across the queue's items. The currently
  playing track takes the first slot and keeps playing — toggling shuffle never interrupts
  playback, restarts a track, or changes what is playing now.
- **Disabling shuffle** clears `shuffle_position` and playback resumes following `position`
  from wherever the current track sits in it.
- **Enabling shuffle again** generates a fresh order. It does not restore a previous one.
- **Play next** inserts immediately after the currently playing item in whichever order is
  active, and takes a `position` in the authored order as well.
- **Add to end** appends to the end of both orders.
- Removing an item and clearing the queue behave identically in both orders.

`repeat_mode` is `off`, `all`, or `one`, and applies to the active play order:

| Mode | At the end of the play order |
|---|---|
| `off` | Playback stops |
| `all` | Wraps to the first item |
| `one` | The current item repeats; advancing manually still moves to the next item |

Restoring a queue on launch restores its shuffled order, not just the fact that shuffle was
on — the queue comes back exactly as it was left.

---

## 9. Collections

v1: static, ordered, manually curated lists of tracks. Create, rename, delete, add, remove,
reorder by drag.

Collections reference `track_id`, so membership survives file moves and tag edits.
Collections are **global**, not scoped to a sublibrary.

---

## 10. Playback service

### XPC interface (sketch)

```swift
@objc protocol PlaybackServiceProtocol {
    func load(url: URL, startAtMs: Int, reply: @escaping (PlaybackError?) -> Void)
    func enqueueNext(url: URL?)                  // nil clears; enables gapless
    func play()
    func pause()
    func stop()
    func seek(toMs: Int)
    func setVolume(_ level: Float)
    func queryState(reply: @escaping (Data) -> Void)
}

@objc protocol PlaybackClientProtocol {         // service → app callbacks
    func stateChanged(_ encoded: Data)
    func trackEnded(url: URL, playedMs: Int, completed: Bool)
    func advancedToNext(url: URL)
    func failed(url: URL, error: PlaybackError)
}
```

### Behavior

- Gapless is handled by SFBAudioEngine's `AudioPlayer` decoder queue. The app calls
  `enqueueNext` as soon as the next item is known. **Enqueue exactly one track ahead** — the
  app owns queue semantics, the service does not.
- MP3 encoder delay and padding are handled by SFBAudioEngine's own MP3 decoder. This was a
  known limitation in v0.1 under AVAudioEngine and is now resolved.
- Position updates published at ~10Hz while playing, not per-buffer.
- On XPC interruption, the app restarts the service and resumes at the last reported position.
- Handle output device changes and sleep/wake by pausing and re-establishing the player rather
  than attempting to continue through the transition.

---

## 11. Artwork pipeline

An art-forward album grid over ~50k tracks cannot read artwork from files on demand. This is a
subsystem, not a detail — it is the single most likely cause of a janky grid.

- Extract artwork at **scan time**, not display time, via SFBAudioEngine's attached-picture API.
- Sources: embedded tags first, then sidecar files in the file's directory
  (`cover.*`, `folder.*`, `front.*`).
- Deduplicate by SHA-256. Many tracks share one image.
- Generate and cache on disk at three sizes: thumb (~128pt), medium (~512pt), full (original).
  Store at `@2x` for Retina.
- Cache location: `~/Library/Caches/`, fully rebuildable, never stored as blobs in the database.
- Grid loads thumbs lazily on scroll with a prefetch window, decoded off the main thread.
- Albums without artwork get a generated placeholder derived from the album title, not a generic
  music-note icon.

---

## 12. UI

**Direction:** minimal, art-forward. Generous whitespace, artwork as the primary visual element,
chrome kept out of the way.

### Structure

- Sidebar: Albums, Artists, Genres, Collections, Queues
- Sublibrary dropdown in the toolbar, applying globally
- Album grid as the default view
- Persistent now-playing bar with artwork, transport, and scrubber

### Views

| View | Presentation |
|---|---|
| Albums | Artwork grid, sortable by title / artist / year / date added |
| Artists | List → artist detail showing their albums as a grid |
| Genres | List → filtered album grid |
| Album detail | Large artwork, track listing, disc groupings where `disc_count > 1` |
| Search results | Flat track list — **the only flat track view in the app** |
| Queue | Reorderable list, current item highlighted |

There is deliberately **no top-level "All Tracks" view.** A flat list appears only as search
results.

### AppKit is mandatory in these places

- **Search results list.** Potentially tens of thousands of rows. Use `NSTableView` via
  `NSViewRepresentable`. SwiftUI `List`/`Table` will not hold 60fps at this scale.
- **Drag-and-drop reordering** in queues and collections, if SwiftUI's `onMove` proves
  insufficient for the interaction quality wanted.

The album grid can start as SwiftUI `LazyVGrid` and move to `NSCollectionView` if it doesn't
hold frame rate — measure before deciding.

---

## 13. Search

- Global typeahead, incremental, results as you type.
- FTS5 over title, artist, album artist, album, genre.
- **Scoped to the active sublibrary by default, with a visible toggle to search globally.**
- Results grouped by entity type (tracks, albums, artists) with a flat track list beneath.
- Debounce input ~150ms; run queries off the main thread; cancel superseded queries.

---

## 14. Tag editing

The app writes tags back to files via SFBAudioEngine's `AudioFile` metadata API. This is the
only write path to user data and must be conservative.

- Single-track and batch edit.
- Fields: title, artist, album artist, album, track no, disc no, year, genre, artwork.

### Write scope: all backing files

A tag edit writes to **every** file backing the track, not just the preferred one.

This is safe because watched roots are always-available local storage (§2) and because bit-identical
copies carrying divergent tags is itself an inconsistent state worth correcting. The payoff is that
files remain the source of truth for tag data with no precedence rule needed: after any successful
edit, the database and every file on disk agree. Edits made in external tag editors are picked up on
the next rescan for free.

**Preflight requirement.** Before applying any edit, verify every backing file is present and
writable. If any is not, refuse the edit entirely and tell the user which file is unavailable.
Never perform a partial write across copies — a half-applied edit reintroduces exactly the
divergence this design exists to prevent.

### Mechanics

- Write atomically per file: temp file, then `rename(2)`. Never edit in place.
- Suppress the FSEvents-triggered rescan for files the app itself just wrote — otherwise every
  edit causes a redundant re-read.
- `audio_hash` must not change on tag edit (§6). Assert this in tests.
- Format specifics are SFBAudioEngine's concern, but WAV tagging is poorly standardized. Decide
  on a convention, document it, and verify round-trip behavior against a fixture file.

---

## 15. Performance targets

| Metric | Target |
|---|---|
| Cold launch to interactive | < 1s |
| Album grid scroll | 60fps sustained (120 on ProMotion) |
| Search first results, 50k tracks | < 50ms |
| Sublibrary switch, full UI update | < 100ms |
| Full rescan, 50k tracks | < 5 min |
| Incremental FSEvents update | < 1s |
| Memory, idle with 50k tracks | < 400MB |

The rescan target is only achievable with the byte-level hashing in §6. If a decode-based
approach creeps back in, this target is unreachable.

Scanning must never block the UI. Show progress; keep the library usable during a scan.

---

## 16. Open questions

1. **ReplayGain** — read existing tags and apply? Compute on scan? Ignore in v1?
2. **Crossfade** — in scope for v1?
3. **Ratings and play counts** — schema is present, but is there UI in v1?
4. **Playlist import** — read existing `.m3u` / `.m3u8` into collections?
5. **Output device selection** in-app, or defer to system default?
6. **Mini player / menu bar item** — in scope?
7. **Keyboard shortcuts** — full set, or media keys only?
8. **First-run onboarding** — how are watched folders configured initially?
9. ~~**Shuffle and repeat semantics** — shuffle the queue in place, or a play-order
   overlay?~~ **Resolved:** play-order overlay, with shuffle and repeat as per-queue
   persisted state. Specified in §8, recorded in
   [ADR 0011](adr/0011-shuffle-as-a-play-order-overlay.md). Numbering is left intact so
   existing references still resolve.
10. **Sort defaults per view**, and are they persisted per-view?
11. **Backup/export** for database-only data (ratings, play counts, collections, queues).

---

## 17. Build notes

- Single Xcode project, two targets: app + XPC service, plus a shared framework for models
  and the rules engine.
- SFBAudioEngine via SPM, linked by both targets.
- App Sandbox on from the start. Retrofitting security-scoped bookmarks later is painful.
- Database migrations versioned from day one — the schema will change.
- The rules engine, scanner, and identity hashing should be unit-testable without a UI.
- Build a fixture library of MP3/FLAC/WAV files with known-awkward cases: missing album artist,
  multi-disc, compilations, non-ASCII tags, embedded and sidecar artwork, bit-identical duplicates
  across two roots, divergent tags on identical audio, FLAC with a zeroed STREAMINFO MD5.
- License audit of SFBAudioEngine's vendored dependencies before any public distribution (§4).
