# 0004. Identify tracks by byte-level audio hash, never by path or decoded audio

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §5, §6

## Context

Watched roots are arbitrary folders whose internal structure is explicitly irregular and
carries no meaning. Files move between roots. The same file may exist in several roots at
once. Everything the user sees must therefore derive from tags, not from directory layout.

Identity must be stable across tag edits — editing a title cannot create a new track and
orphan its play count, rating, and collection membership.

The full-rescan target is 50,000 tracks in under 5 minutes (§15).

## Decision

**File paths are not identity.** Each track is identified by an `audio_hash` computed from
file bytes only, covering the audio stream and excluding all metadata regions:

| Format | Source of hash |
|---|---|
| FLAC | The MD5 of unencoded audio already in the STREAMINFO block — zero cost. If absent or all-zero, fall back to hashing frame bytes. |
| MP3 | SHA-256 over MPEG frame bytes, with ID3v1, ID3v2, and APE regions excluded. |
| WAV | SHA-256 over the contents of the `data` chunk. |

For MP3 and WAV, bound the I/O: hash the first 1MB and last 1MB of audio bytes plus the
total audio byte length.

**Never decode to hash.** Files sharing an `audio_hash` collapse into one `tracks` row with
N `files` rows behind it; `preferred_file_id` selects which copy plays.

Album grouping uses `album_key` — normalized, lowercased, whitespace-collapsed
`(album_artist ?? artist) + album_title + year` — and is explicitly not path-derived.

## Consequences

- Tag edits never change identity. **This is a test assertion, not an aspiration:** editing
  any tag field must leave `audio_hash` unchanged. If it does not, the implementation is
  wrong.
- An album split across two watched roots is one album.
- Bit-identical duplicates collapse automatically without user intervention.
- Hashing is I/O-bound and bounded, which is what makes the 5-minute rescan target
  reachable. **If a decode-based approach ever creeps back in, that target becomes
  unreachable.**
- Only bit-identical copies are detected. A FLAC and an MP3 of the same song hash
  differently and remain separate tracks; cross-format duplicate detection is out of scope
  (§2).
- Truncated hashing (first/last 1MB) is theoretically defeatable by two files differing
  only in the middle. Accepted: the failure mode requires deliberately crafted input, and
  reading hundreds of gigabytes per rescan is not.
- Divergent tags across bit-identical copies are possible at scan time. The preferred
  file's tags populate the `tracks` row; the divergence is surfaced in the UI and
  correctable via [0007](0007-tag-edits-write-to-all-backing-files.md).

## Alternatives considered

**Path as identity.** Simple and free. Rejected outright: files move between roots, exist
in multiple roots simultaneously, and folder structure carries no meaning. Every move
would orphan ratings and play counts.

**Decoded-audio fingerprint.** Would catch cross-format duplicates and survive re-encoding.
Rejected because decoding 50k files takes hours, blowing the §15 rescan target by orders of
magnitude — and cross-format duplicate detection is an explicit non-goal.

**Hashing the entire file including tags.** Trivial to implement. Rejected because any tag
edit would change identity, which is the exact failure this decision prevents.

**Acoustic fingerprinting (Chromaprint / AcoustID).** Robust across encodes and a network
dependency. Rejected on both the decode cost above and the scope of a v1 (§2).
