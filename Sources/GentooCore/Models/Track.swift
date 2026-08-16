import GRDB

///
/// One logical track — the thing the library shows once, however many copies back it (§5, §6).
///
/// `audioHash` is the identity and the only non-null tag-independent field. Every tag column
/// is nullable because tags are what files actually carry, not what they ought to: a file with
/// no title is a real file, and refusing to represent it would mean refusing to scan it.
///
/// Tag columns are a **cache of what is on disk** (§5). Files remain the source of truth, and
/// after any successful edit (§14) the database and every backing file agree. `playCount`,
/// `lastPlayedAt`, and `rating` are the exception: they exist only here and are the reason the
/// database needs a backup story.
///
public struct Track: IdentifiedRecord, Equatable {
    public static let databaseTableName = "tracks"

    public enum CodingKeys: String, CodingKey {
        case id
        case audioHash = "audio_hash"
        case preferredFileID = "preferred_file_id"
        case albumID = "album_id"
        case title
        case artist
        case artistSort = "artist_sort"
        case albumArtist = "album_artist"
        case trackNo = "track_no"
        case discNo = "disc_no"
        case year
        case genre
        case durationMs = "duration_ms"
        case musicbrainzTrackID = "musicbrainz_track_id"
        case addedAt = "added_at"
        case playCount = "play_count"
        case lastPlayedAt = "last_played_at"
        case rating
    }

    public var id: Int64?
    /// Identity (§6). Unchanged by any tag edit — assert this in tests.
    public var audioHash: String
    /// Which backing copy plays. Nil until the scanner has picked one.
    public var preferredFileID: Int64?
    public var albumID: Int64?
    public var title: String?
    public var artist: String?
    public var artistSort: String?
    public var albumArtist: String?
    public var trackNo: Int?
    public var discNo: Int?
    public var year: Int?
    public var genre: String?
    public var durationMs: Int?
    public var musicbrainzTrackID: String?
    /// Unix epoch seconds.
    public var addedAt: Int64
    public var playCount: Int
    /// Unix epoch seconds.
    public var lastPlayedAt: Int64?
    /// 0–5, or nil for unrated.
    public var rating: Int?

    public init(
        id: Int64? = nil,
        audioHash: String,
        preferredFileID: Int64? = nil,
        albumID: Int64? = nil,
        title: String? = nil,
        artist: String? = nil,
        artistSort: String? = nil,
        albumArtist: String? = nil,
        trackNo: Int? = nil,
        discNo: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        durationMs: Int? = nil,
        musicbrainzTrackID: String? = nil,
        addedAt: Int64,
        playCount: Int = 0,
        lastPlayedAt: Int64? = nil,
        rating: Int? = nil
    ) {
        self.id = id
        self.audioHash = audioHash
        self.preferredFileID = preferredFileID
        self.albumID = albumID
        self.title = title
        self.artist = artist
        self.artistSort = artistSort
        self.albumArtist = albumArtist
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.genre = genre
        self.durationMs = durationMs
        self.musicbrainzTrackID = musicbrainzTrackID
        self.addedAt = addedAt
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.rating = rating
    }
}
