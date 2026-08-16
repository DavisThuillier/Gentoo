import GRDB
import Testing

@testable import GentooCore

///
/// Smoke tests for the package scaffold.
///
/// These assert nothing about Gentoo's behavior — there is none yet. They prove the things
/// every later test silently depends on: that GRDB links, that the in-memory helper hands
/// back a usable and isolated database, and that the linked SQLite build actually provides
/// the two features §5's schema is written against. Finding out at M4 that FTS5 is missing
/// would be an expensive way to learn it.
///
@Suite("Package scaffold")
struct ScaffoldTests {
    ///
    /// The in-memory helper
    ///

    @Test("An in-memory database opens and executes SQL")
    func inMemoryDatabaseExecutesSQL() throws {
        let count = try TestDatabase.withDatabase { db in
            try db.execute(sql: "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO t (name) VALUES (?)", arguments: ["Gentoo"])
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM t")
        }

        #expect(count == 1)
    }

    @Test("Each in-memory database is independent")
    func inMemoryDatabasesAreIsolated() throws {
        let first = try TestDatabase.make()
        let second = try TestDatabase.make()

        try first.write { db in
            try db.execute(sql: "CREATE TABLE t (id INTEGER PRIMARY KEY)")
        }

        // Unnamed `:memory:` databases are private to their connection. If this ever fails,
        // parallel tests are sharing state and every later suite is suspect.
        let visible = try second.read { db in try db.tableExists("t") }
        #expect(visible == false)
    }

    ///
    /// SQLite features the §5 schema is written against
    ///

    @Test("Foreign keys are enforced")
    func foreignKeysAreEnforced() throws {
        try TestDatabase.withDatabase { db in
            #expect(try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") == true)

            try db.execute(sql: "CREATE TABLE parent (id INTEGER PRIMARY KEY)")
            try db.execute(
                sql: """
                    CREATE TABLE child (
                      id         INTEGER PRIMARY KEY,
                      parent_id  INTEGER NOT NULL REFERENCES parent(id) ON DELETE CASCADE
                    )
                    """
            )

            // §5 leans on ON DELETE CASCADE for collection_items, queue_items, and files.
            // SQLite ships with foreign keys off by default; GRDB turns them on.
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "INSERT INTO child (parent_id) VALUES (1)")
            }

            try db.execute(sql: "INSERT INTO parent (id) VALUES (1)")
            try db.execute(sql: "INSERT INTO child (parent_id) VALUES (1)")
            try db.execute(sql: "DELETE FROM parent WHERE id = 1")

            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM child") == 0)
        }
    }

    @Test("FTS5 is available and matches across diacritics")
    func fts5MatchesAcrossDiacritics() throws {
        try TestDatabase.withDatabase { db in
            // Verbatim from §5, because the tokenizer options are the load-bearing part:
            // ADR 0005 chose `remove_diacritics 2` so non-ASCII tags search without the
            // user transliterating.
            try db.execute(
                sql: """
                    CREATE VIRTUAL TABLE tracks_fts USING fts5(
                      title, artist, album_artist, album, genre,
                      content='', tokenize='unicode61 remove_diacritics 2'
                    )
                    """
            )

            try db.execute(
                sql: """
                    INSERT INTO tracks_fts (rowid, title, artist, album_artist, album, genre)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [1, "Jóga", "Björk", "Björk", "Homogenic", "Electronic"]
            )

            let matches = try Int.fetchAll(
                db,
                sql: "SELECT rowid FROM tracks_fts WHERE tracks_fts MATCH ?",
                arguments: ["bjork"]
            )
            #expect(matches == [1])
        }
    }
}
