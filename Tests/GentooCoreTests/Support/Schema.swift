import GRDB

///
/// Reading the schema back out of a database.
///
/// Tests assert against what SQLite actually built, not against the SQL that was submitted —
/// otherwise a migration test only proves that a string literal is equal to itself.
///
enum Schema {
    ///
    /// The names of every table the migrations created, sorted.
    ///
    /// Three kinds of table are excluded, none of which are ours to assert on:
    ///
    /// - `sqlite_%`, SQLite's own bookkeeping
    /// - `grdb_migrations`, where GRDB records what it has applied
    /// - the shadow tables backing a virtual table (`tracks_fts_data` and friends), which
    ///   are an implementation detail of FTS5 and change with the SQLite version. The
    ///   virtual table itself is kept.
    ///
    /// Shadow tables are found by prefix against the virtual tables actually present, rather
    /// than by matching known FTS5 suffixes. Matching `%_config` and `%_data` would quietly
    /// swallow a real table that happened to be named that way, and a schema test that hides
    /// tables is worse than no schema test.
    ///
    static func userTableNames(_ db: Database) throws -> [String] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT name, sql FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%'
                  AND name <> 'grdb_migrations'
                """
        )

        let names = rows.map { $0["name"] as String }
        let virtualTables = rows
            .filter { ($0["sql"] as String?)?.uppercased().hasPrefix("CREATE VIRTUAL TABLE") == true }
            .map { $0["name"] as String }

        return
            names
            .filter { name in !virtualTables.contains { name.hasPrefix("\($0)_") } }
            .sorted()
    }

    ///
    /// Every schema object the migrations created, as name → the SQL SQLite stored for it.
    ///
    /// Used to compare a schema against itself across a redundant migration. Includes
    /// indexes and virtual tables; excludes SQLite's own objects and GRDB's migration log,
    /// which is expected to be identical anyway but is not what is under test.
    ///
    static func definitions(_ db: Database) throws -> [String: String] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT name, sql FROM sqlite_master
                WHERE name NOT LIKE 'sqlite_%'
                  AND name <> 'grdb_migrations'
                  AND sql IS NOT NULL
                """
        )

        return Dictionary(uniqueKeysWithValues: rows.map { ($0["name"] as String, $0["sql"] as String) })
    }
}
