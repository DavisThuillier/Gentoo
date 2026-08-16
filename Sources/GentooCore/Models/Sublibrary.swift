import GRDB

///
/// A persistent global lens over the library (§7).
///
/// `ruleJSON` is the §7 rule document, stored as text. It is deliberately opaque here: the
/// rules engine is a standalone component with no reference to sublibraries (ADR 0006), so the
/// record carries the document and the engine interprets it. Decoding it into a rule model is
/// M3's work (#18), not this type's.
///
/// `position` is the order of the toolbar dropdown.
///
public struct Sublibrary: IdentifiedRecord, Equatable {
    public static let databaseTableName = "sublibraries"

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case ruleJSON = "rule_json"
        case position
        case createdAt = "created_at"
    }

    public var id: Int64?
    public var name: String
    public var ruleJSON: String
    public var position: Int
    /// Unix epoch seconds.
    public var createdAt: Int64

    public init(id: Int64? = nil, name: String, ruleJSON: String, position: Int, createdAt: Int64) {
        self.id = id
        self.name = name
        self.ruleJSON = ruleJSON
        self.position = position
        self.createdAt = createdAt
    }
}
