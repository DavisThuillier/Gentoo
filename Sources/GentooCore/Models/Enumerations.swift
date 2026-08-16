import GRDB

///
/// The enum-backed columns of §5.
///
/// Each is stored as the TEXT its raw value spells, matching the comment §5 puts beside the
/// column. They are `CaseIterable` so a test can round-trip every case rather than the two
/// someone thought of, which is the failure mode these types exist to prevent.
///
/// Deliberately not `Codable`-only: conforming to `DatabaseValueConvertible` means these can
/// also be bound directly into a query, which the rules engine will need (§7) without going
/// through a record.
///

///
/// The audio formats Gentoo reads (§2). Three, and no more in v1.
///
public enum AudioFormat: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case mp3
    case flac
    case wav
}

///
/// What the last scan found for a file (§6).
///
/// `missing` is not a deletion. Files that vanish are retained and their tracks stay in the
/// library, greyed and unplayable, so that play counts, ratings, and collection membership
/// survive a file moving or a volume being unplugged.
///
public enum ScanState: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case ok
    case missing
    case error
}

///
/// Where a piece of artwork came from (§11).
///
/// Embedded tags are preferred; sidecars (`cover.*`, `folder.*`, `front.*`) are the fallback.
///
public enum ArtworkSource: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case embedded
    case sidecar
}

///
/// What happens at the end of a queue's play order (§8, ADR 0011).
///
/// Per queue, not global: each named queue remembers its own.
///
public enum RepeatMode: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    /// Playback stops at the end of the play order.
    case off

    /// The play order wraps to its first item.
    case all

    /// The current item repeats. Advancing manually still moves to the next item.
    case one
}
