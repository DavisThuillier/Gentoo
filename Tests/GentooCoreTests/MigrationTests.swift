import GRDB
import Testing

@testable import GentooCore

///
/// The migration framework itself, independent of what any particular migration creates.
///
/// Two properties matter and neither is obvious from reading the code: that migrations are
/// the *only* thing that builds the schema, and that running them against a current database
/// changes nothing. §17 requires versioned migrations from day one; these are the assertions
/// that make "versioned" mean something.
///
@Suite("Migrations")
struct MigrationTests {
    ///
    /// A fresh database is built entirely by migration
    ///

    @Test("A fresh database has no schema before migrating")
    func freshDatabaseIsEmpty() throws {
        let tables = try TestDatabase.withDatabase { db in
            try Schema.userTableNames(db)
        }

        // If this ever fails, something creates a table outside the migrator and the
        // schema is no longer defined in one place.
        #expect(tables.isEmpty)
    }

    @Test("Migrating a fresh database records every migration")
    func migratingRecordsEveryMigration() throws {
        let library = try TestDatabase.migrated()

        let (applied, completed) = try library.writer.read { db in
            (
                try LibraryMigrator.migrator.appliedMigrations(db),
                try LibraryMigrator.migrator.hasCompletedMigrations(db)
            )
        }

        #expect(applied == LibraryMigrator.identifiers)
        #expect(completed)
    }

    @Test("The migrator knows the initial schema and nothing it has not been given")
    func migratorRegistersKnownMigrations() throws {
        #expect(LibraryMigrator.identifiers == ["0001_initial_schema"])
    }

    ///
    /// Migrating twice is a no-op
    ///

    @Test("Migrating an already-migrated database leaves the schema untouched")
    func secondMigrationDoesNotChangeSchema() throws {
        let library = try TestDatabase.migrated()

        let before = try library.writer.read { db in try Schema.definitions(db) }
        try LibraryMigrator.migrator.migrate(library.writer)
        let after = try library.writer.read { db in try Schema.definitions(db) }

        #expect(before == after)
        #expect(before.isEmpty == false)  // guards against comparing two empty schemas
    }

    @Test("Migrating an already-migrated database applies nothing a second time")
    func secondMigrationAppliesNothing() throws {
        let library = try TestDatabase.migrated()

        let before = try library.writer.read { db in
            try LibraryMigrator.migrator.appliedMigrations(db)
        }
        try LibraryMigrator.migrator.migrate(library.writer)
        let after = try library.writer.read { db in
            try LibraryMigrator.migrator.appliedMigrations(db)
        }

        #expect(before == after)
        #expect(after == LibraryMigrator.identifiers)
    }

    @Test("Data survives a redundant migration")
    func secondMigrationPreservesData() throws {
        let library = try TestDatabase.migrated()

        try library.writer.write { db in
            try db.execute(
                sql: "INSERT INTO collections (name, created_at) VALUES (?, ?)",
                arguments: ["Late Night", 0]
            )
        }

        // A migration that recreated tables it had already created would pass a
        // schema-only comparison and still destroy the library.
        try LibraryMigrator.migrator.migrate(library.writer)

        let name = try library.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM collections")
        }
        #expect(name == "Late Night")
    }

    ///
    /// Opening
    ///

    @Test("Opening a library migrates it")
    func openingMigrates() throws {
        // LibraryDatabase has no initializer that skips migration, so holding one is the
        // proof that the schema is current. This asserts that is actually true.
        let library = try LibraryDatabase.inMemory()

        let completed = try library.writer.read { db in
            try LibraryMigrator.migrator.hasCompletedMigrations(db)
        }
        #expect(completed)
    }

    @Test("Foreign keys are enforced on a library connection")
    func foreignKeysEnabled() throws {
        let enabled = try TestDatabase.withMigratedDatabase { db in
            try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        #expect(enabled == true)
    }
}
