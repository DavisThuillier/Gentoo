import GRDB

///
/// One listening event (§5).
///
/// Append-only, and distinct from `Track.playCount`: the count is the fast answer for sorting
/// and display, this is the record of what actually happened. `completed` separates a track
/// played through from one skipped after a few seconds, which a bare count cannot.
///
/// Like ratings and collections, this exists only in the database — no file carries it.
///
public struct PlayHistory: IdentifiedRecord, Equatable {
    public static let databaseTableName = "play_history"

    public enum CodingKeys: String, CodingKey {
        case id
        case trackID = "track_id"
        case playedAt = "played_at"
        case msPlayed = "ms_played"
        case completed
    }

    public var id: Int64?
    public var trackID: Int64
    /// Unix epoch seconds.
    public var playedAt: Int64
    public var msPlayed: Int
    public var completed: Bool

    public init(id: Int64? = nil, trackID: Int64, playedAt: Int64, msPlayed: Int, completed: Bool) {
        self.id = id
        self.trackID = trackID
        self.playedAt = playedAt
        self.msPlayed = msPlayed
        self.completed = completed
    }
}
