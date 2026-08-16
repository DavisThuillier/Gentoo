import GRDB

///
/// The initial schema — spec §5, in full.
///
/// The DDL is written as SQL rather than through GRDB's `create(table:)` DSL so that it can
/// be diffed against §5 by eye. §5 is written as SQL and is the source of truth; a
/// translation layer between the two would be one more place for them to disagree.
///
/// Forward references are deliberate and safe: `files` references `tracks` before `tracks`
/// exists, and `tracks` references `albums` before `albums` does. SQLite resolves foreign
/// key targets at statement time, not at `CREATE TABLE` time, so the creation order can
/// follow §5's reading order rather than a dependency order. By the end of the migration
/// every target exists.
///
enum V1InitialSchema {
    ///
    /// Migration identifiers are permanent. GRDB records the applied ones in its
    /// `grdb_migrations` table, so renaming this string makes every existing database look
    /// unmigrated and re-run the migration against tables that are already there. Add
    /// migrations; never rename them.
    ///
    static let identifier = "0001_initial_schema"

    static func migrate(_ db: Database) throws {
        //
        // Roots and files
        //

        try db.execute(
            sql: """
                CREATE TABLE roots (
                  id                 INTEGER PRIMARY KEY,
                  path               TEXT NOT NULL UNIQUE,
                  bookmark           BLOB,
                  enabled            INTEGER NOT NULL DEFAULT 1,
                  last_full_scan_at  INTEGER
                )
                """
        )

        try db.execute(
            sql: """
                CREATE TABLE files (
                  id            INTEGER PRIMARY KEY,
                  root_id       INTEGER NOT NULL REFERENCES roots(id) ON DELETE CASCADE,
                  track_id      INTEGER REFERENCES tracks(id),
                  path          TEXT NOT NULL UNIQUE,
                  size          INTEGER NOT NULL,
                  mtime         INTEGER NOT NULL,
                  format        TEXT NOT NULL,
                  audio_hash    TEXT,
                  sample_rate   INTEGER,
                  channels      INTEGER,
                  bit_depth     INTEGER,
                  bitrate       INTEGER,
                  duration_ms   INTEGER,
                  scan_state    TEXT NOT NULL,
                  scan_error    TEXT,
                  last_seen_at  INTEGER NOT NULL
                )
                """
        )
        try db.execute(sql: "CREATE INDEX idx_files_track ON files(track_id)")
        try db.execute(sql: "CREATE INDEX idx_files_hash ON files(audio_hash)")

        //
        // Tracks, albums, artists
        //

        try db.execute(
            sql: """
                CREATE TABLE tracks (
                  id                     INTEGER PRIMARY KEY,
                  audio_hash             TEXT NOT NULL UNIQUE,
                  preferred_file_id      INTEGER REFERENCES files(id),
                  album_id               INTEGER REFERENCES albums(id),
                  title                  TEXT,
                  artist                 TEXT,
                  artist_sort            TEXT,
                  album_artist           TEXT,
                  track_no               INTEGER,
                  disc_no                INTEGER,
                  year                   INTEGER,
                  genre                  TEXT,
                  duration_ms            INTEGER,
                  musicbrainz_track_id   TEXT,
                  added_at               INTEGER NOT NULL,
                  play_count             INTEGER NOT NULL DEFAULT 0,
                  last_played_at         INTEGER,
                  rating                 INTEGER
                )
                """
        )
        try db.execute(sql: "CREATE INDEX idx_tracks_album ON tracks(album_id)")

        try db.execute(
            sql: """
                CREATE TABLE albums (
                  id                       INTEGER PRIMARY KEY,
                  album_key                TEXT NOT NULL UNIQUE,
                  title                    TEXT,
                  album_artist             TEXT,
                  album_artist_sort        TEXT,
                  year                     INTEGER,
                  disc_count               INTEGER,
                  is_compilation           INTEGER NOT NULL DEFAULT 0,
                  artwork_id               INTEGER REFERENCES artwork(id),
                  musicbrainz_release_id   TEXT
                )
                """
        )

        try db.execute(
            sql: """
                CREATE TABLE artists (
                  id          INTEGER PRIMARY KEY,
                  name        TEXT NOT NULL UNIQUE,
                  sort_name   TEXT
                )
                """
        )

        //
        // Artwork
        //

        try db.execute(
            sql: """
                CREATE TABLE artwork (
                  id            INTEGER PRIMARY KEY,
                  sha256        TEXT NOT NULL UNIQUE,
                  source        TEXT NOT NULL,
                  width         INTEGER,
                  height        INTEGER,
                  path_thumb    TEXT,
                  path_medium   TEXT,
                  path_full     TEXT
                )
                """
        )

        //
        // Sublibraries and collections
        //

        try db.execute(
            sql: """
                CREATE TABLE sublibraries (
                  id          INTEGER PRIMARY KEY,
                  name        TEXT NOT NULL,
                  rule_json   TEXT NOT NULL,
                  position    INTEGER NOT NULL,
                  created_at  INTEGER NOT NULL
                )
                """
        )

        try db.execute(
            sql: """
                CREATE TABLE collections (
                  id          INTEGER PRIMARY KEY,
                  name        TEXT NOT NULL,
                  created_at  INTEGER NOT NULL
                )
                """
        )

        try db.execute(
            sql: """
                CREATE TABLE collection_items (
                  collection_id  INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
                  track_id       INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                  position       INTEGER NOT NULL,
                  PRIMARY KEY (collection_id, position)
                )
                """
        )

        //
        // Queues
        //

        try db.execute(
            sql: """
                CREATE TABLE queues (
                  id                INTEGER PRIMARY KEY,
                  name              TEXT NOT NULL,
                  is_active         INTEGER NOT NULL DEFAULT 0,
                  shuffle_enabled   INTEGER NOT NULL DEFAULT 0,
                  repeat_mode       TEXT NOT NULL DEFAULT 'off',
                  created_at        INTEGER NOT NULL
                )
                """
        )

        // `position` is the authored order and `shuffle_position` the play order when
        // shuffled (§8, ADR 0011). Both use gaps of 1024 so an insertion into either is a
        // single-row update.
        try db.execute(
            sql: """
                CREATE TABLE queue_items (
                  queue_id          INTEGER NOT NULL REFERENCES queues(id) ON DELETE CASCADE,
                  track_id          INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                  position          INTEGER NOT NULL,
                  shuffle_position  INTEGER,
                  PRIMARY KEY (queue_id, position)
                )
                """
        )

        // SQLite treats NULLs as distinct in a unique index, so this keeps the shuffled
        // order collision-free without needing a partial index for the unshuffled case.
        try db.execute(
            sql: "CREATE UNIQUE INDEX idx_queue_items_shuffle ON queue_items(queue_id, shuffle_position)"
        )

        //
        // History
        //

        try db.execute(
            sql: """
                CREATE TABLE play_history (
                  id         INTEGER PRIMARY KEY,
                  track_id   INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                  played_at  INTEGER NOT NULL,
                  ms_played  INTEGER NOT NULL,
                  completed  INTEGER NOT NULL
                )
                """
        )

        //
        // Search
        //

        // `content=''` makes this contentless: FTS5 stores the index and nothing else, and
        // syncing it is the writer's job. Nothing here is automatic, and no triggers are
        // created — M4 maintains the index on every write path that changes searchable text.
        //
        // `remove_diacritics 2` is the load-bearing option (ADR 0005): non-ASCII tags must
        // be searchable without the user transliterating them.
        try db.execute(
            sql: """
                CREATE VIRTUAL TABLE tracks_fts USING fts5(
                  title, artist, album_artist, album, genre,
                  content='', tokenize='unicode61 remove_diacritics 2'
                )
                """
        )
    }
}
