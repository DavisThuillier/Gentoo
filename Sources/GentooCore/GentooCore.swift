///
/// GentooCore holds everything the app and the XPC service can share and nothing either of
/// them needs a UI framework for: the SQLite schema and its migrations (§5, §17), track
/// identity and `audio_hash` (§6), album grouping (§6), the rules engine (§7), and the
/// query layer that threads the sublibrary predicate (§7).
///
/// It deliberately does *not* hold: SwiftUI or AppKit types, XPC plumbing, `MPNowPlayingInfoCenter`
/// mirroring, or anything that reads a security-scoped bookmark. See ADR 0008 for why the
/// boundary sits here, and ADR 0006 for why the rules engine in particular has no reference
/// to its consumers.
///
/// This file carries the module's documentation and no code. The first types arrive with
/// the initial migration.
///
