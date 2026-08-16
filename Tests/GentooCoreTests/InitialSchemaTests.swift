import GRDB
import Testing

@testable import GentooCore

///
/// The shape of a §5 table, transcribed from the spec.
///
/// Deliberately a second transcription rather than something derived from the migration —
/// a test that reads its expectations out of the code under test proves only that the code
/// is self-consistent. §5 is the source of truth, and this is what holds the migration to it.
///
struct TableShape: Sendable, CustomStringConvertible {
    let name: String
    let columns: [String]
    let notNull: Set<String>

    var description: String { name }
}

private let expectedTables: [TableShape] = [
    TableShape(
        name: "roots",
        columns: ["id", "path", "bookmark", "enabled", "last_full_scan_at"],
        notNull: ["path", "enabled"]
    ),
    TableShape(
        name: "files",
        columns: [
            "id", "root_id", "track_id", "path", "size", "mtime", "format", "audio_hash",
            "sample_rate", "channels", "bit_depth", "bitrate", "duration_ms", "scan_state",
            "scan_error", "last_seen_at",
        ],
        notNull: ["root_id", "path", "size", "mtime", "format", "scan_state", "last_seen_at"]
    ),
    TableShape(
        name: "tracks",
        columns: [
            "id", "audio_hash", "preferred_file_id", "album_id", "title", "artist",
            "artist_sort", "album_artist", "track_no", "disc_no", "year", "genre",
            "duration_ms", "musicbrainz_track_id", "added_at", "play_count",
            "last_played_at", "rating",
        ],
        notNull: ["audio_hash", "added_at", "play_count"]
    ),
    TableShape(
        name: "albums",
        columns: [
            "id", "album_key", "title", "album_artist", "album_artist_sort", "year",
            "disc_count", "is_compilation", "artwork_id", "musicbrainz_release_id",
        ],
        notNull: ["album_key", "is_compilation"]
    ),
    TableShape(
        name: "artists",
        columns: ["id", "name", "sort_name"],
        notNull: ["name"]
    ),
    TableShape(
        name: "artwork",
        columns: ["id", "sha256", "source", "width", "height", "path_thumb", "path_medium", "path_full"],
        notNull: ["sha256", "source"]
    ),
    TableShape(
        name: "sublibraries",
        columns: ["id", "name", "rule_json", "position", "created_at"],
        notNull: ["name", "rule_json", "position", "created_at"]
    ),
    TableShape(
        name: "collections",
        columns: ["id", "name", "created_at"],
        notNull: ["name", "created_at"]
    ),
    TableShape(
        name: "collection_items",
        columns: ["collection_id", "track_id", "position"],
        notNull: ["collection_id", "track_id", "position"]
    ),
    TableShape(
        name: "queues",
        columns: ["id", "name", "is_active", "shuffle_enabled", "repeat_mode", "created_at"],
        notNull: ["name", "is_active", "shuffle_enabled", "repeat_mode", "created_at"]
    ),
    TableShape(
        name: "queue_items",
        columns: ["queue_id", "track_id", "position", "shuffle_position"],
        notNull: ["queue_id", "track_id", "position"]
    ),
    TableShape(
        name: "play_history",
        columns: ["id", "track_id", "played_at", "ms_played", "completed"],
        notNull: ["track_id", "played_at", "ms_played", "completed"]
    ),
    TableShape(
        name: "tracks_fts",
        columns: ["title", "artist", "album_artist", "album", "genre"],
        notNull: []
    ),
]

///
/// The initial migration builds §5 exactly.
///
/// The §5 schema is the contract every later milestone codes against — the rules engine
/// compiles predicates over these column names, the scanner writes these tables, and the
/// query layer joins them. Drift between the spec and what the migration builds is the
/// expensive kind of bug, so it is asserted rather than assumed.
///
@Suite("Initial schema (§5)")
struct InitialSchemaTests {
    ///
    /// Tables and columns
    ///

    @Test("The database holds exactly the §5 tables")
    func schemaHoldsExactlySpecTables() throws {
        let actual = try TestDatabase.withMigratedDatabase { db in
            try Schema.userTableNames(db)
        }

        #expect(actual == expectedTables.map(\.name).sorted())
    }

    @Test("Each table has exactly its §5 columns", arguments: expectedTables)
    func tableHasSpecColumns(_ table: TableShape) throws {
        let actual = try TestDatabase.withMigratedDatabase { db in
            try db.columns(in: table.name).map(\.name)
        }

        // Order matters here on purpose: §5 lists columns in a deliberate order, and a
        // reordering is drift even though SQLite would not care.
        #expect(actual == table.columns)
    }

    @Test("Each table's NOT NULL columns match §5", arguments: expectedTables)
    func tableHasSpecNullability(_ table: TableShape) throws {
        let actual = try TestDatabase.withMigratedDatabase { db in
            Set(try db.columns(in: table.name).filter(\.isNotNull).map(\.name))
        }

        // `id INTEGER PRIMARY KEY` is SQLite's rowid alias: it is implicitly NOT NULL but
        // reported as nullable, so it never appears in either set.
        #expect(actual == table.notNull)
    }

    @Test("Defaults match §5")
    func defaultsMatchSpec() throws {
        let defaults = try TestDatabase.withMigratedDatabase { db -> [String: String] in
            var found: [String: String] = [:]
            for table in ["roots", "tracks", "albums", "queues"] {
                for column in try db.columns(in: table) {
                    found["\(table).\(column.name)"] = column.defaultValueSQL
                }
            }
            return found
        }

        #expect(defaults["roots.enabled"] == "1")
        #expect(defaults["tracks.play_count"] == "0")
        #expect(defaults["albums.is_compilation"] == "0")
        #expect(defaults["queues.is_active"] == "0")

        // ADR 0011: shuffle is off and repeat is off on a new queue.
        #expect(defaults["queues.shuffle_enabled"] == "0")
        #expect(defaults["queues.repeat_mode"] == "'off'")
    }

    ///
    /// Indexes
    ///

    @Test(
        "The §5 indexes exist",
        arguments: [
            ("files", "idx_files_track", ["track_id"]),
            ("files", "idx_files_hash", ["audio_hash"]),
            ("tracks", "idx_tracks_album", ["album_id"]),
            ("queue_items", "idx_queue_items_shuffle", ["queue_id", "shuffle_position"]),
        ]
    )
    func indexExists(_ table: String, _ name: String, _ columns: [String]) throws {
        let index = try TestDatabase.withMigratedDatabase { db in
            try db.indexes(on: table).first { $0.name == name }
        }

        #expect(index != nil)
        #expect(index?.columns == columns)
    }

    @Test("The shuffle overlay index is unique")
    func shuffleIndexIsUnique() throws {
        let index = try TestDatabase.withMigratedDatabase { db in
            try db.indexes(on: "queue_items").first { $0.name == "idx_queue_items_shuffle" }
        }

        #expect(index?.isUnique == true)
    }

    ///
    /// Uniqueness constraints
    ///

    @Test(
        "§5's unique columns reject a duplicate",
        arguments: [
            ("roots", "INSERT INTO roots (path) VALUES ('/Music')"),
            ("tracks", "INSERT INTO tracks (audio_hash, added_at) VALUES ('abc', 0)"),
            ("albums", "INSERT INTO albums (album_key) VALUES ('bjork|homogenic|1997')"),
            ("artists", "INSERT INTO artists (name) VALUES ('Björk')"),
            ("artwork", "INSERT INTO artwork (sha256, source) VALUES ('deadbeef', 'embedded')"),
        ]
    )
    func uniqueColumnRejectsDuplicate(_ table: String, _ insert: String) throws {
        try TestDatabase.withMigratedDatabase { db in
            try db.execute(sql: insert)
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: insert)
            }
        }
    }

    ///
    /// Cascades
    ///
    /// §5 leans on ON DELETE CASCADE so that deleting a container does not leave orphans
    /// behind. Each of these is a row that must disappear on its own.
    ///

    @Test("Deleting a root deletes its files")
    func deletingRootCascadesToFiles() throws {
        try TestDatabase.withMigratedDatabase { db in
            try db.execute(sql: "INSERT INTO roots (id, path) VALUES (1, '/Music')")
            try db.execute(
                sql: """
                    INSERT INTO files (root_id, path, size, mtime, format, scan_state, last_seen_at)
                    VALUES (1, '/Music/a.flac', 1, 1, 'flac', 'ok', 0)
                    """
            )

            try db.execute(sql: "DELETE FROM roots WHERE id = 1")

            let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM files")
            #expect(remaining == 0)
        }
    }

    @Test("Deleting a track deletes its queue, collection, and history rows")
    func deletingTrackCascades() throws {
        try TestDatabase.withMigratedDatabase { db in
            try db.execute(sql: "INSERT INTO tracks (id, audio_hash, added_at) VALUES (1, 'abc', 0)")
            try db.execute(sql: "INSERT INTO queues (id, name, created_at) VALUES (1, 'Up Next', 0)")
            try db.execute(sql: "INSERT INTO collections (id, name, created_at) VALUES (1, 'Faves', 0)")
            try db.execute(sql: "INSERT INTO queue_items (queue_id, track_id, position) VALUES (1, 1, 1024)")
            try db.execute(
                sql: "INSERT INTO collection_items (collection_id, track_id, position) VALUES (1, 1, 1024)"
            )
            try db.execute(
                sql: """
                    INSERT INTO play_history (track_id, played_at, ms_played, completed)
                    VALUES (1, 0, 1000, 1)
                    """
            )

            try db.execute(sql: "DELETE FROM tracks WHERE id = 1")

            let queued = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM queue_items")
            let collected = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM collection_items")
            let history = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM play_history")

            #expect(queued == 0)
            #expect(collected == 0)
            #expect(history == 0)
        }
    }

    @Test("Deleting a queue deletes its items but not the tracks")
    func deletingQueueCascadesToItemsOnly() throws {
        try TestDatabase.withMigratedDatabase { db in
            try db.execute(sql: "INSERT INTO tracks (id, audio_hash, added_at) VALUES (1, 'abc', 0)")
            try db.execute(sql: "INSERT INTO queues (id, name, created_at) VALUES (1, 'Up Next', 0)")
            try db.execute(sql: "INSERT INTO queue_items (queue_id, track_id, position) VALUES (1, 1, 1024)")

            try db.execute(sql: "DELETE FROM queues WHERE id = 1")

            let items = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM queue_items")
            let tracks = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks")

            #expect(items == 0)
            #expect(tracks == 1)
        }
    }

    ///
    /// The shuffle overlay (§8, ADR 0011)
    ///

    @Test("An unshuffled queue may hold many items with no shuffle position")
    func manyNullShufflePositionsAreAllowed() throws {
        try TestDatabase.withMigratedDatabase { db in
            try seedQueue(db, queueID: 1, trackIDs: [1, 2, 3])

            // SQLite treats NULLs as distinct in a unique index. If it did not, the
            // unshuffled case would need a partial index and this would fail.
            let unshuffled = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM queue_items WHERE shuffle_position IS NULL"
            )
            #expect(unshuffled == 3)
        }
    }

    @Test("A queue cannot hold two items at the same shuffle position")
    func duplicateShufflePositionIsRejected() throws {
        try TestDatabase.withMigratedDatabase { db in
            try seedQueue(db, queueID: 1, trackIDs: [1, 2])

            try db.execute(sql: "UPDATE queue_items SET shuffle_position = 1024 WHERE track_id = 1")

            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "UPDATE queue_items SET shuffle_position = 1024 WHERE track_id = 2")
            }
        }
    }

    @Test("Two queues may use the same shuffle positions")
    func shufflePositionsAreScopedToTheQueue() throws {
        try TestDatabase.withMigratedDatabase { db in
            try seedQueue(db, queueID: 1, trackIDs: [1])
            try seedQueue(db, queueID: 2, trackIDs: [2])

            // Queues are independent objects (§8); one being shuffled says nothing about
            // another.
            try db.execute(sql: "UPDATE queue_items SET shuffle_position = 1024")

            let shuffled = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM queue_items WHERE shuffle_position = 1024"
            )
            #expect(shuffled == 2)
        }
    }

    @Test("Shuffling does not touch the authored order")
    func authoredOrderSurvivesShuffling() throws {
        try TestDatabase.withMigratedDatabase { db in
            try seedQueue(db, queueID: 1, trackIDs: [1, 2, 3])

            // ADR 0011: `position` is authored order and is never mutated by shuffling, so
            // turning shuffle off restores it exactly. This is the schema-level half of
            // that claim — that the two orders can coexist on one row.
            try db.execute(sql: "UPDATE queue_items SET shuffle_position = 3072 WHERE track_id = 1")
            try db.execute(sql: "UPDATE queue_items SET shuffle_position = 1024 WHERE track_id = 2")
            try db.execute(sql: "UPDATE queue_items SET shuffle_position = 2048 WHERE track_id = 3")

            let authored = try Int.fetchAll(
                db,
                sql: "SELECT track_id FROM queue_items WHERE queue_id = 1 ORDER BY position"
            )
            let play = try Int.fetchAll(
                db,
                sql: "SELECT track_id FROM queue_items WHERE queue_id = 1 ORDER BY shuffle_position"
            )

            #expect(authored == [1, 2, 3])
            #expect(play == [2, 3, 1])
        }
    }

    ///
    /// Search
    ///

    @Test("tracks_fts matches across diacritics")
    func ftsMatchesAcrossDiacritics() throws {
        try TestDatabase.withMigratedDatabase { db in
            // ScaffoldTests proves the linked SQLite has FTS5 at all. This proves the table
            // the migration built carries `remove_diacritics 2` (ADR 0005), which is what
            // lets non-ASCII tags be searched without transliterating them.
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

    @Test("tracks_fts is contentless, so nothing syncs it automatically")
    func ftsIsContentless() throws {
        try TestDatabase.withMigratedDatabase { db in
            try db.execute(sql: "INSERT INTO tracks (id, audio_hash, title, added_at) VALUES (1, 'abc', 'Jóga', 0)")

            // `content=''` means the index is the writer's responsibility and no triggers
            // exist. M4 maintains it on every write path; a future change that adds triggers
            // to the migration should fail here and be argued for on purpose.
            let matches = try Int.fetchAll(
                db,
                sql: "SELECT rowid FROM tracks_fts WHERE tracks_fts MATCH ?",
                arguments: ["joga"]
            )
            #expect(matches.isEmpty)
        }
    }
}

///
/// Inserts a queue with `trackIDs` in authored order, gapped by 1024 per §8.
///
private func seedQueue(_ db: Database, queueID: Int, trackIDs: [Int]) throws {
    try db.execute(
        sql: "INSERT INTO queues (id, name, created_at) VALUES (?, ?, 0)",
        arguments: [queueID, "Queue \(queueID)"]
    )

    for (offset, trackID) in trackIDs.enumerated() {
        try db.execute(
            sql: "INSERT OR IGNORE INTO tracks (id, audio_hash, added_at) VALUES (?, ?, 0)",
            arguments: [trackID, "hash-\(trackID)"]
        )
        try db.execute(
            sql: "INSERT INTO queue_items (queue_id, track_id, position) VALUES (?, ?, ?)",
            arguments: [queueID, trackID, (offset + 1) * 1024]
        )
    }
}
