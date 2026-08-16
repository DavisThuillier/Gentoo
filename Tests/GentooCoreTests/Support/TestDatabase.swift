import GRDB

///
/// An isolated in-memory library database.
///
/// Every call opens an independent `:memory:` database. SQLite keeps an unnamed in-memory
/// database private to its connection, so tests running in parallel — Swift Testing's
/// default — cannot see one another's writes, and none of them touch the disk.
///
/// Once the initial migration exists (§17), this is where it gets applied, so that a test
/// database and a real one are never configured differently.
///
enum TestDatabase {
    ///
    /// Opens an independent in-memory database.
    ///
    static func make(configuration: Configuration = Configuration()) throws -> DatabaseQueue {
        try DatabaseQueue(configuration: configuration)
    }

    ///
    /// Opens an independent in-memory database and runs `body` against it inside a
    /// transaction. The database is released when the call returns.
    ///
    static func withDatabase<T>(
        configuration: Configuration = Configuration(),
        _ body: (Database) throws -> T
    ) throws -> T {
        try make(configuration: configuration).write(body)
    }
}
