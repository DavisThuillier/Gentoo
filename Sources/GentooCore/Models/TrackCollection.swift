import GRDB

///
/// A static, ordered, manually curated list of tracks (§9).
///
/// **Named `TrackCollection`, not `Collection`.** The domain word is "collection" and the UI
/// says so, but a type named `Collection` in this module would shadow `Swift.Collection`
/// everywhere — and the rules engine and query layer are generic code that needs the protocol.
/// Renaming one model type is cheaper than writing `Swift.Collection` for the life of the
/// package.
///
/// Collections reference tracks, not files, so membership survives a file moving or being
/// retagged. They are **global** — never scoped to a sublibrary (§9).
///
public struct TrackCollection: IdentifiedRecord, Equatable {
    public static let databaseTableName = "collections"

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
    }

    public var id: Int64?
    public var name: String
    /// Unix epoch seconds.
    public var createdAt: Int64

    public init(id: Int64? = nil, name: String, createdAt: Int64) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

///
/// One track's membership in a collection, at a position.
///
/// Keyed by `(collectionID, position)` with no surrogate id, so this is a `PersistableRecord`
/// rather than an `IdentifiedRecord` — there is nothing for an insert to write back.
///
/// `position` is gapped in increments of 1024, as queues are (§8), so a drag-reorder is a
/// single-row update rather than a renumber of the whole list.
///
public struct CollectionItem: LibraryRecord, PersistableRecord, Equatable {
    public static let databaseTableName = "collection_items"

    public enum CodingKeys: String, CodingKey {
        case collectionID = "collection_id"
        case trackID = "track_id"
        case position
    }

    public var collectionID: Int64
    public var trackID: Int64
    public var position: Int

    public init(collectionID: Int64, trackID: Int64, position: Int) {
        self.collectionID = collectionID
        self.trackID = trackID
        self.position = position
    }
}
