import GRDB

///
/// The shared shape of every §5 record type.
///
/// Records are immutable value types crossing actor boundaries constantly — scanning is
/// non-isolated, UI state is `@MainActor` — so `Sendable` is a conformance every record needs
/// rather than one each declares.
///
/// ## Why every record spells out its own `CodingKeys`
///
/// §5's columns are `snake_case` and Swift properties are `camelCase`, and GRDB offers
/// `convertToSnakeCase` / `convertFromSnakeCase` to bridge that without hand-written keys.
/// They are not used here, because the pair is **not symmetric across acronyms**:
///
/// ```
/// convertToSnakeCase("rootID")    == "root_id"    // encodes fine
/// convertFromSnakeCase("root_id") == "rootId"     // ... decodes to a different name
/// ```
///
/// A property named `rootID` or `ruleJSON` therefore writes correctly and reads back as a key
/// that no longer exists. For a non-optional property that throws, which is survivable. **For
/// an optional it silently decodes as nil** — `Album.artworkID` came back empty from a row
/// that plainly had one, with no error anywhere. Losing every album's artwork link on read is
/// not a failure mode worth trading for shorter model files.
///
/// The alternative was renaming properties to `rootId` and `ruleJson` so the round trip
/// closes. Rejected: it bends Swift naming for a serialization detail, and it leaves the trap
/// armed for whoever adds the next property with an acronym in it. Explicit keys remove the
/// class of bug rather than the instance, and they make the mapping to §5 greppable.
///
/// `ModelRoundTripTests` holds every record to this, in both directions.
///
public protocol LibraryRecord: Codable, FetchableRecord, EncodableRecord, TableRecord, Sendable {}

///
/// A record whose table has an `INTEGER PRIMARY KEY` — SQLite's rowid alias.
///
/// `id` is nil until the row is inserted, at which point SQLite assigns one and `didInsert`
/// writes it back. Every §5 table has one except `collection_items` and `queue_items`, which
/// are keyed by `(container, position)` and have nothing to write back.
///
public protocol IdentifiedRecord: LibraryRecord, MutablePersistableRecord {
    var id: Int64? { get set }
}

extension IdentifiedRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
