# 0002. Use SFBAudioEngine for both playback and tag I/O

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §4
**Supersedes:** the AVAudioEngine choice recorded in spec v0.1

## Context

The app must **write** tags back to files (§14). AVFoundation can read metadata but has no
write path short of re-encoding, which is unacceptable for lossless files. So a
third-party tag library is required no matter what is chosen for playback.

Spec v0.1 selected AVAudioEngine on the rationale of "first-party frameworks only, nothing
to vendor or license-audit," and accepted degraded MP3 gapless playback as a known
limitation. Once a third-party dependency is mandatory for tag writing, that rationale is
spent.

## Decision

Use SFBAudioEngine for both concerns: `AudioPlayer` for playback, `AudioFile` for tag read
and write. Integrate via SPM, building from source. Link it from both the app and the XPC
service targets.

## Consequences

- MP3 encoder delay and padding are handled correctly by SFBAudioEngine's own MP3 decoder.
  The gapless limitation accepted in v0.1 is resolved rather than documented.
- One dependency instead of two, one API surface, one set of format quirks to learn.
- Building from source via SPM keeps codesigning straightforward — nothing prebuilt to
  notarize separately.
- Third-party decoder code now sits in the audio path, which is the direct motivation for
  the process split in [0001](0001-client-server-process-split.md).
- **A licensing audit is required before any public distribution.** SFBAudioEngine's own
  license is permissive, but it vendors third-party decoders and TagLib, each with their
  own terms. TagLib is settled: its dual LGPL/MPL licensing permits static linking into a
  closed application, with copyleft scoped to modifications of TagLib's own files. The
  decoder dependencies need individual audit; any that are LGPL-only require dynamic
  linking or shipping relinkable objects. This is a compliance checklist, not a blocker,
  but it must happen before shipping rather than after.
- WAV tagging is poorly standardized. A convention must be chosen, documented, and
  verified for round-trip behavior against a fixture file.

## Alternatives considered

**AVFoundation for tag writing.** Reads fine; has no write path short of re-encoding,
which would destroy lossless audio. **Do not propose this again.**

**MPD as the playback server.** Supports only one `music_directory` and cannot handle
multiple watched roots without a symlink farm. Tags are read-only. It maintains a single
server-side queue, conflicting with the multi-queue model in §8. Its path-tree data model
conflicts with metadata-first indexing ([0004](0004-metadata-first-identity-without-decoding.md)).
GPL-2.0 complicates later distribution.

**libmpv.** LGPL-buildable, but carries a video player's entire surface area to decode
three audio formats, and provides no library layer at all.

**Rust + Symphonia.** Better decode control and real-time safety. Rejected because that
buys playback fidelity, which is priority #4 of 4 (§1), at the cost of an FFI boundary, a
hand-rolled IPC protocol, and a second toolchain — all of which cost priority #3, smallest
shippable v1.

**Hand-rolled tag parsing.** Weeks of work plus a long edge-case tail on real-world
malformed tags. Rejected against priority #3.
