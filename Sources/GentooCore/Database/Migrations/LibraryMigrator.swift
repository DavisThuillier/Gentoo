import GRDB

///
/// The library schema, as an ordered list of versioned migrations (§17).
///
/// There is no other way the schema comes into existence. A fresh database is an empty file
/// that migrations build; nothing creates a table outside this list, including tests. The
/// point is that the database a test runs against and the database a user has are configured
/// identically, so "works in tests" means something.
///
/// **Every schema change ships a versioned migration in the same commit.** Adding one is a
/// single line here plus the file that implements it.
///
public enum LibraryMigrator {
    ///
    /// Every migration, in the order they apply.
    ///
    /// Order is the order of this array, not lexicographic order of identifiers — GRDB
    /// applies migrations in registration order. Append; do not insert into the middle.
    ///
    private static let migrations: [Migration] = [
        Migration(identifier: V1InitialSchema.identifier, migrate: V1InitialSchema.migrate)
    ]

    ///
    /// The identifiers of every known migration, in application order.
    ///
    /// Derived from `migrations` rather than maintained alongside it, so the two cannot
    /// disagree about what the schema is.
    ///
    public static var identifiers: [String] {
        migrations.map(\.identifier)
    }

    ///
    /// A migrator with every known migration registered.
    ///
    /// Built per call rather than held as a shared value. It is cheap — registering a
    /// migration stores a closure — and it keeps the type free of mutable global state that
    /// Swift 6 would then have to be convinced is safe.
    ///
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // `eraseDatabaseOnSchemaChange` is deliberately left off. It is a development
        // convenience that silently deletes the database when the schema drifts, and the
        // library holds ratings, play counts, collections, and queues that exist nowhere
        // else (§5). Losing those to a convenience flag is not an acceptable failure mode.

        for migration in migrations {
            migrator.registerMigration(migration.identifier, migrate: migration.migrate)
        }

        return migrator
    }

    ///
    /// One registered migration: a permanent identifier and the schema change it performs.
    ///
    private struct Migration {
        let identifier: String
        let migrate: @Sendable (Database) throws -> Void
    }
}
