import Foundation
import GRDB

///
/// A watched folder (§6).
///
/// Structure inside a root is irregular and carries no meaning — everything is derived from
/// tags, never from the folder tree.
///
/// `bookmark` is a security-scoped bookmark rather than a path, because under App Sandbox a
/// path alone does not survive a restart. It is nil until the app target exists to create one
/// (M7); the core package never resolves it.
///
public struct Root: IdentifiedRecord, Equatable {
    public static let databaseTableName = "roots"

    public enum CodingKeys: String, CodingKey {
        case id
        case path
        case bookmark
        case enabled
        case lastFullScanAt = "last_full_scan_at"
    }

    public var id: Int64?
    public var path: String
    public var bookmark: Data?
    public var enabled: Bool
    /// Unix epoch seconds.
    public var lastFullScanAt: Int64?

    public init(
        id: Int64? = nil,
        path: String,
        bookmark: Data? = nil,
        enabled: Bool = true,
        lastFullScanAt: Int64? = nil
    ) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.enabled = enabled
        self.lastFullScanAt = lastFullScanAt
    }
}
