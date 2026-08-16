import GRDB

///
/// A playback queue (§8).
///
/// There is always exactly one active queue, and switching which is active does not stop
/// playback. Queues are **independent of the active sublibrary** — switching lenses never
/// modifies, filters, or clears one, and a queue may hold tracks the current lens would hide.
///
/// `shuffleEnabled` and `repeatMode` are per-queue rather than global application state
/// (ADR 0011), so a queue restored on launch comes back exactly as it was left.
///
public struct Queue: IdentifiedRecord, Equatable {
    public static let databaseTableName = "queues"

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
        case shuffleEnabled = "shuffle_enabled"
        case repeatMode = "repeat_mode"
        case createdAt = "created_at"
    }

    public var id: Int64?
    public var name: String
    public var isActive: Bool
    public var shuffleEnabled: Bool
    public var repeatMode: RepeatMode
    /// Unix epoch seconds.
    public var createdAt: Int64

    public init(
        id: Int64? = nil,
        name: String,
        isActive: Bool = false,
        shuffleEnabled: Bool = false,
        repeatMode: RepeatMode = .off,
        createdAt: Int64
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.shuffleEnabled = shuffleEnabled
        self.repeatMode = repeatMode
        self.createdAt = createdAt
    }
}

///
/// One track's place in a queue, in both orders (§8, ADR 0011).
///
/// `position` is the **authored** order and is never mutated by shuffling. `shufflePosition`
/// is the play order while the queue's `shuffleEnabled` is set, and nil otherwise — which is
/// what lets toggling shuffle off restore the authored order exactly, because it was never
/// lost.
///
/// Both use gaps of 1024 so inserting into either is a single-row update.
///
public struct QueueItem: LibraryRecord, PersistableRecord, Equatable {
    public static let databaseTableName = "queue_items"

    public enum CodingKeys: String, CodingKey {
        case queueID = "queue_id"
        case trackID = "track_id"
        case position
        case shufflePosition = "shuffle_position"
    }

    public var queueID: Int64
    public var trackID: Int64
    /// Authored order. Never mutated by shuffling.
    public var position: Int
    /// Play order while shuffled; nil when not. Unique within a queue.
    public var shufflePosition: Int?

    public init(queueID: Int64, trackID: Int64, position: Int, shufflePosition: Int? = nil) {
        self.queueID = queueID
        self.trackID = trackID
        self.position = position
        self.shufflePosition = shufflePosition
    }
}
