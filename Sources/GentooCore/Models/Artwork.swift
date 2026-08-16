import GRDB

///
/// A piece of cover art, deduplicated by content (§11).
///
/// **The image itself is never here.** The three cached sizes live on disk under
/// `~/Library/Caches/` and these columns hold their paths; §11 forbids image blobs in the
/// database. The cache is fully rebuildable, so a nil path is a cache miss, not data loss.
///
/// `sha256` is over the image bytes, which is what makes one row serve every track sharing a
/// cover — the common case for an album.
///
public struct Artwork: IdentifiedRecord, Equatable {
    public static let databaseTableName = "artwork"

    public enum CodingKeys: String, CodingKey {
        case id
        case sha256
        case source
        case width
        case height
        case pathThumb = "path_thumb"
        case pathMedium = "path_medium"
        case pathFull = "path_full"
    }

    public var id: Int64?
    public var sha256: String
    public var source: ArtworkSource
    public var width: Int?
    public var height: Int?
    /// ~128pt, at `@2x`.
    public var pathThumb: String?
    /// ~512pt, at `@2x`.
    public var pathMedium: String?
    /// Original size.
    public var pathFull: String?

    public init(
        id: Int64? = nil,
        sha256: String,
        source: ArtworkSource,
        width: Int? = nil,
        height: Int? = nil,
        pathThumb: String? = nil,
        pathMedium: String? = nil,
        pathFull: String? = nil
    ) {
        self.id = id
        self.sha256 = sha256
        self.source = source
        self.width = width
        self.height = height
        self.pathThumb = pathThumb
        self.pathMedium = pathMedium
        self.pathFull = pathFull
    }
}
