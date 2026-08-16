# Gentoo

A native macOS music player. An art-forward SwiftUI/AppKit client owns the library,
browsing, queues, and collections; a bundled XPC service owns decode and audio output. The
client never touches an audio buffer; the service never knows what a collection is.

**Behavior is defined by [docs/spec.md](docs/spec.md).** Decisions and their rejected
alternatives live in [docs/adr/](docs/adr/). Read the relevant spec section before changing
behavior it defines, and cite it in the commit body.

---

## Status

M0. The `GentooCore` package builds and `swift test` runs green; the schema, migrations,
and model types are not in place yet. There is no app target and nothing runnable.

The build is sequenced **core-first** ([ADR 0008](docs/adr/0008-core-first-swiftpm-package.md)):
the shared framework ships as a standalone SwiftPM package, testable with the Command Line
Tools alone. The Xcode project consuming it is added once that core is proven.

Xcode 26.x is required before the app target, XPC service, App Sandbox, security-scoped
bookmarks, or any Instruments profiling. Nothing up to that point needs it — M0–M5 build
and test with the Command Line Tools alone, which is the whole point of the sequencing.

## Commands

Core package — works without Xcode:

```
swift build
swift test
swift test --filter IdentityTests
```

App and XPC service — requires Xcode 26.x:

```
xcodebuild -scheme Gentoo -destination 'platform=macOS' build
xcodebuild -scheme Gentoo -destination 'platform=macOS' test
```

## Priorities

When a tradeoff has no clean answer, resolve it in this order (§1). This ordering is
deliberate and load-bearing:

1. **UI polish**
2. **Large-library performance**
3. **Smallest shippable v1**
4. **Playback fidelity**

Where a choice trades fidelity for simplicity or polish, take it.

## Invariants

Load-bearing. Violating one is a correctness bug, not a style disagreement.

**Never decode to hash (§6).** `audio_hash` is computed from file bytes only — FLAC from
the STREAMINFO MD5, falling back to frame bytes when absent or zeroed; MP3 from MPEG frame
bytes with ID3v1/ID3v2/APE excluded; WAV from the `data` chunk. MP3 and WAV bound I/O to
the first and last 1MB plus total audio byte length. A decode-based path makes the
5-minute/50k rescan target unreachable.

**A tag edit must not change `audio_hash` (§6, §14).** Assert this in tests.

**Paths are not identity (§5).** Files move between roots and exist in several at once.
Everything derives from tags and `audio_hash`. Album grouping uses `album_key`; it is never
path-derived.

**The XPC service is a transport, not a queue manager (§3).** It holds the current track
plus at most one enqueued next track for gapless. All ordering, advancing, shuffle, repeat,
and queue switching lives in the app. The service never reads the database. SFBAudioEngine's
`AudioPlayer` has its own internal decoder queue — **do not use it as the app's queue.**

**Now Playing lives in the app process (§3).** `MPNowPlayingInfoCenter` and
`MPRemoteCommandCenter` do not work correctly from an XPC service. The app mirrors engine
state upward and publishes it.

**Every library query takes a sublibrary predicate (§7).** There is no code path that reads
the library without going through it. Rules compile to parameterized SQL — **never
string-interpolate a rule value.** `path` predicates match any backing file, not just the
preferred one.

**Tag edits are all-or-nothing across backing files (§14).** Preflight every file for
presence and writability; refuse the entire edit if any fails. Write atomically per file
(temp then `rename(2)`), never in place. Suppress the FSEvents rescan the app's own write
triggers.

**Artwork is extracted at scan time, never at display time (§11).** Three sizes cached on
disk under `~/Library/Caches/`, deduplicated by SHA-256, decoded off the main thread. Never
store image blobs in the database.

**Every schema change ships a versioned migration in the same commit (§17).**

**Scanning never blocks the UI (§15).** Show progress; keep the library usable throughout.

## Do not propose

Settled in the ADRs and recorded so they are not relitigated. If you believe one should be
reopened, **say so explicitly and state what new information changes the analysis** — do not
quietly reintroduce it.

- **AVFoundation for tag writing.** No write path short of re-encoding, which destroys
  lossless audio. The spec says: do not propose this again. ([0002](docs/adr/0002-sfbaudioengine-for-playback-and-tag-io.md))
- **MPD as the playback server.** One `music_directory`, read-only tags, single server-side
  queue, GPL-2.0. ([0002](docs/adr/0002-sfbaudioengine-for-playback-and-tag-io.md))
- **libmpv.** A video player's surface area for three audio formats, with no library layer.
  ([0002](docs/adr/0002-sfbaudioengine-for-playback-and-tag-io.md))
- **Rust + Symphonia.** Buys fidelity — priority #4 — at the cost of an FFI boundary, a
  hand-rolled IPC protocol, and a second toolchain. ([0002](docs/adr/0002-sfbaudioengine-for-playback-and-tag-io.md))
- **Hand-rolled tag parsing.** ([0002](docs/adr/0002-sfbaudioengine-for-playback-and-tag-io.md))
- **Tauri, Electron, or any web UI.** ([0003](docs/adr/0003-native-swiftui-appkit-ui.md))
- **Path-based or decode-based track identity.** ([0004](docs/adr/0004-metadata-first-identity-without-decoding.md))
- **Core Data or SwiftData.** ([0005](docs/adr/0005-sqlite-via-grdb.md))
- **A top-level "All Tracks" view.** A flat track list appears only as search results (§12).
- **SwiftUI `List`/`Table` for search results.** Use `NSTableView` via `NSViewRepresentable`;
  tens of thousands of rows will not hold 60fps otherwise (§12).

## Performance budget

Changes are **measured** against §15, not assumed to meet it:

| Metric | Target |
|---|---|
| Cold launch to interactive | < 1s |
| Album grid scroll | 60fps sustained (120 on ProMotion) |
| Search first results, 50k tracks | < 50ms |
| Sublibrary switch, full UI update | < 100ms |
| Full rescan, 50k tracks | < 5 min |
| Incremental FSEvents update | < 1s |
| Memory, idle with 50k tracks | < 400MB |

The album grid may start as SwiftUI `LazyVGrid` and move to `NSCollectionView` if it does
not hold frame rate — **measure before deciding** (§12).

## Commits

Conventional Commits, enforced by `.githooks/commit-msg` locally and by CI on PR titles.

```
<type>(<scope>): <subject>
```

**Types:** `feat` `fix` `perf` `refactor` `docs` `test` `build` `ci` `chore` `revert`.
Breaking changes take `!` after the scope plus a `BREAKING CHANGE:` footer.

**Scopes:** `library` `scanner` `identity` `playback` `xpc` `rules` `queue` `collections`
`artwork` `ui` `search` `tags` `db` `build` `adr` `claude` `deps` `release`.

Subject in the imperative mood, no trailing period, 72 characters or fewer. The body
explains **why**, wrapped at 72. Commits produced with AI assistance carry:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```

Work happens on short-lived branches (`feat/rules-engine`, `fix/flac-md5-fallback`) and
lands on `main` via **squash-merged PR**, so the **PR title must itself be a valid
Conventional Commit** — it becomes the subject on `main`. `main` stays linear.

**Never commit, push, or open a PR unless asked.**

## Code style

- Swift 6 strict concurrency. Actor isolation is deliberate, not incidental: `@MainActor`
  on UI state, non-isolated on scanning and hashing paths.
- **The core package imports neither SwiftUI nor AppKit.** A type that needs a UI framework
  belongs in the app target ([0008](docs/adr/0008-core-first-swiftpm-package.md)).
- The rules engine, scanner, and identity hashing are unit-testable without a UI. Keep it
  that way (§17).
- Separate labeled blocks of code with:

  ```
  ###
  ### Label
  ###
  ```

- Comment density and naming should match surrounding code. Explain why, not what.

## Test fixtures

§17 requires a fixture library of MP3/FLAC/WAV files covering known-awkward cases: missing
album artist, multi-disc, compilations, non-ASCII tags, embedded and sidecar artwork,
bit-identical duplicates across two roots, divergent tags on identical audio, and FLAC with
a zeroed STREAMINFO MD5. Fixtures are marked binary in `.gitattributes`.

## Layout

```
docs/spec.md      Implementation spec v0.2 — source of truth for behavior
docs/adr/         Architecture decision records
.claude/agents/   Specialist review agents
.githooks/        Commit message validator, shared with CI
```

## Specialist agents

Delegate to these rather than reviewing their domain ad hoc:

| Agent | Use for |
|---|---|
| `spec-auditor` | Conformance to the spec; drift, and relitigated rejections |
| `db-guardian` | Schema, migrations, query paths, sublibrary predicate threading, SQL safety |
| `swift-concurrency-reviewer` | Actor isolation, `@MainActor`, XPC threading, main-thread blocking |
| `perf-guard` | Any change touching the §15 budget — scan, grid, search, memory |

## Open questions

§16 lists eleven product questions, ten of them still open: ReplayGain, crossfade,
ratings/play-count UI, playlist import, output device selection, mini player, keyboard
shortcuts, first-run onboarding, sort defaults, and backup/export for database-only data.

Question 9, shuffle and repeat semantics, is resolved — a play-order overlay with per-queue
state ([ADR 0011](docs/adr/0011-shuffle-as-a-play-order-overlay.md), §8). §16's numbering is
kept intact so existing references still resolve.

**Do not resolve these unilaterally.** Raise the question, get an answer, record it in the
spec, then implement.
