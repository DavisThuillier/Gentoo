import GRDB

@testable import GentooCore

///
/// An isolated in-memory library database.
///
/// Every call opens an independent `:memory:` database. SQLite keeps an unnamed in-memory
/// database private to its connection, so tests running in parallel — Swift Testing's
/// default — cannot see one another's writes, and none of them touch the disk.
///
/// The migrated helpers go through `LibraryDatabase`, the same path a real library takes, so
/// a test database and a real one are never configured differently. The raw helpers exist for
/// tests that need a database with no schema — proving what migrations create, mostly.
///
enum TestDatabase {
    ///
    /// Raw — no schema
    ///

    ///
    /// Opens an independent in-memory database with no migrations applied.
    ///
    static func make(configuration: Configuration = Configuration()) throws -> DatabaseQueue {
        try DatabaseQueue(configuration: configuration)
    }

    ///
    /// Opens an independent, unmigrated in-memory database and runs `body` against it inside
    /// a transaction. The database is released when the call returns.
    ///
    static func withDatabase<T>(
        configuration: Configuration = Configuration(),
        _ body: (Database) throws -> T
    ) throws -> T {
        try make(configuration: configuration).write(body)
    }

    ///
    /// Migrated — the §5 schema
    ///

    ///
    /// Opens an independent in-memory library with every migration applied.
    ///
    static func migrated() throws -> LibraryDatabase {
        try LibraryDatabase.inMemory()
    }

    ///
    /// Opens an independent migrated in-memory library and runs `body` against it inside a
    /// transaction. The database is released when the call returns.
    ///
    static func withMigratedDatabase<T>(_ body: (Database) throws -> T) throws -> T {
        try migrated().writer.write(body)
    }
}
