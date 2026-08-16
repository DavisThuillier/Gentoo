import GRDB

///
/// An album (§6).
///
/// `albumKey` is the grouping identity: normalized, lowercased, whitespace-collapsed
/// `(album_artist ?? artist) + album_title + year`. **Explicitly not path-derived** — an album
/// split across two watched roots is one album, and a folder holding two albums is two.
///
/// `isCompilation` marks the case where `album_artist` is absent and track artists differ.
/// Those group under a compilation identity rather than fragmenting into one album per artist.
///
public struct Album: IdentifiedRecord, Equatable {
    public static let databaseTableName = "albums"

    public enum CodingKeys: String, CodingKey {
        case id
        case albumKey = "album_key"
        case title
        case albumArtist = "album_artist"
        case albumArtistSort = "album_artist_sort"
        case year
        case discCount = "disc_count"
        case isCompilation = "is_compilation"
        case artworkID = "artwork_id"
        case musicbrainzReleaseID = "musicbrainz_release_id"
    }

    public var id: Int64?
    public var albumKey: String
    public var title: String?
    public var albumArtist: String?
    public var albumArtistSort: String?
    public var year: Int?
    public var discCount: Int?
    public var isCompilation: Bool
    public var artworkID: Int64?
    public var musicbrainzReleaseID: String?

    public init(
        id: Int64? = nil,
        albumKey: String,
        title: String? = nil,
        albumArtist: String? = nil,
        albumArtistSort: String? = nil,
        year: Int? = nil,
        discCount: Int? = nil,
        isCompilation: Bool = false,
        artworkID: Int64? = nil,
        musicbrainzReleaseID: String? = nil
    ) {
        self.id = id
        self.albumKey = albumKey
        self.title = title
        self.albumArtist = albumArtist
        self.albumArtistSort = albumArtistSort
        self.year = year
        self.discCount = discCount
        self.isCompilation = isCompilation
        self.artworkID = artworkID
        self.musicbrainzReleaseID = musicbrainzReleaseID
    }
}
