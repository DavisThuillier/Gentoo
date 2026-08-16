# Gentoo

A native macOS music player for large local libraries.

Minimal and art-forward, built for collections of 10,000–50,000 tracks where folder
structure is irregular and metadata is the only reliable organizing principle. Everything
the interface shows — albums, artists, genres, duplicate detection — is derived from tags
and audio content, never from where a file happens to sit on disk.

> **Status: pre-implementation.** The repository currently holds the specification,
> architecture decision records, and project tooling. No application code yet.

## Design

A client–server split across two processes:

```
┌──────────────────────────────────────┐
│  Gentoo.app  (SwiftUI/AppKit)        │
│                                      │
│  • SQLite library (GRDB)             │
│  • Scanner (FSEvents)                │
│  • Queues, collections, sublibraries │
│  • Artwork cache                     │
│  • Tag writing (SFBAudioEngine)      │
│  • Now Playing / media keys          │
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

The client never touches an audio buffer; the service never knows what a collection is.
The split exists for crash isolation: third-party decoders sit in the audio path, and a
malformed file that kills a decoder must not take the window with it.

| Concern | Choice |
|---|---|
| Language | Swift |
| GUI | SwiftUI, with AppKit where the platform requires it |
| Audio and tag I/O | SFBAudioEngine |
| IPC | NSXPCConnection |
| Database | SQLite via GRDB, FTS5 for search |

**Formats:** MP3, FLAC, WAV. **Platform:** macOS only.

### Notable properties

- **Tags are the source of truth.** The database is a rebuildable cache for tag data. Edits
  are written back to every file backing a track, atomically, or not at all.
- **Identity survives tag edits.** Tracks are identified by a hash of audio bytes only —
  never by path, and never by decoding. Editing a title cannot orphan a play count.
- **Duplicates collapse automatically.** Bit-identical copies across watched roots become
  one library entry with several files behind it.
- **Sublibraries are a global lens.** A metadata rule set that filters every browse view at
  once, compiled to a parameterized SQL predicate threaded through every query.

## Documentation

| | |
|---|---|
| [docs/spec.md](docs/spec.md) | Implementation spec — the source of truth for behavior |
| [docs/adr/](docs/adr/) | Architecture decision records, including rejected alternatives |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Commit conventions, branch flow, local setup |
| [CLAUDE.md](CLAUDE.md) | Project instructions and invariants |

## Building

The shared core is a SwiftPM package and builds with the Command Line Tools alone:

```sh
swift build
swift test
```

The app and XPC service targets require **Xcode 26.x** — they need `.app` bundling,
entitlements, App Sandbox, and codesigning, none of which SwiftPM provides. Instruments,
needed to verify the performance budget, also ships with Xcode.

See [ADR 0008](docs/adr/0008-core-first-swiftpm-package.md) for why the build is sequenced
this way.

## Development

This project is built with [Claude Code](https://claude.com/claude-code) under human
architectural direction. Design decisions, tradeoffs, and rejected alternatives are made
deliberately and recorded in [docs/adr/](docs/adr/) before implementation; the spec is
written and reviewed by hand.

Commits produced with AI assistance carry a `Co-Authored-By: Claude` trailer, so the
history distinguishes assisted work from unassisted rather than leaving it ambiguous.

Contributions follow [Conventional Commits](https://www.conventionalcommits.org/), enforced
by a local git hook and by CI. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE).

Note that SFBAudioEngine vendors third-party decoders and TagLib, each under their own
terms. A dependency license audit is required before any public distribution — see
[ADR 0002](docs/adr/0002-sfbaudioengine-for-playback-and-tag-io.md).
