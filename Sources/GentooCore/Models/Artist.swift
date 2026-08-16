import GRDB

///
/// An artist name, deduplicated (§5).
///
/// `sortName` is what the Artists list orders by, so "The Velvet Underground" files under V.
/// It is nil when no tag supplied one; the sort falls back to `name`.
///
public struct Artist: IdentifiedRecord, Equatable {
    public static let databaseTableName = "artists"

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortName = "sort_name"
    }

    public var id: Int64?
    public var name: String
    public var sortName: String?

    public init(id: Int64? = nil, name: String, sortName: String? = nil) {
        self.id = id
        self.name = name
        self.sortName = sortName
    }
}
