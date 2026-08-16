import Foundation
import GRDB

///
/// The library database: an open connection with every migration applied.
///
/// Holding one of these is the proof that the schema is current — there is no way to
/// construct it that skips migration. Callers get a `DatabaseWriter` and use GRDB directly;
/// this type owns opening, configuring, and migrating, and nothing else.
///
/// **This is a rebuildable cache for tag data** (§5). Files on disk are the source of truth
/// for everything a tag can hold. Ratings, play counts, collections, queues, and
/// sublibraries live only here and are the reason the file is worth protecting.
///
public struct LibraryDatabase: Sendable {
    ///
    /// The migrated connection. Use GRDB's `read` and `write` against it.
    ///
    public let writer: any DatabaseWriter

    ///
    /// Wraps an already-open connection and migrates it to the current schema.
    ///
    /// Migration is idempotent: GRDB applies only the migrations the database has not yet
    /// recorded, so calling this on a current database does nothing.
    ///
    public init(_ writer: any DatabaseWriter) throws {
        try LibraryMigrator.migrator.migrate(writer)
        self.writer = writer
    }

    ///
    /// Opens the library at `url`, creating it if it does not exist, and migrates it.
    ///
    /// A pool rather than a queue, because §15 requires that scanning never blocks the UI.
    /// A pool in WAL mode lets browse queries keep reading while a scan writes; a serialized
    /// queue would make every scan write a stall in front of the album grid.
    ///
    public static func open(at url: URL) throws -> LibraryDatabase {
        try LibraryDatabase(DatabasePool(path: url.path, configuration: makeConfiguration()))
    }

    ///
    /// Opens an independent in-memory library and migrates it.
    ///
    /// Each call is a separate database — SQLite keeps an unnamed `:memory:` database private
    /// to its connection.
    ///
    public static func inMemory() throws -> LibraryDatabase {
        try LibraryDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    ///
    /// The configuration every library connection is opened with.
    ///
    /// Foreign keys are on — GRDB's default, and §5 leans on `ON DELETE CASCADE` for
    /// `collection_items`, `queue_items`, `play_history`, and `files`. It is spelled out
    /// rather than inherited silently, because SQLite's own default is off and a connection
    /// opened without it would drop referential integrity without failing anything.
    ///
    public static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return configuration
    }
}
