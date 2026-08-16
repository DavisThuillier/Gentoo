import Foundation
import GRDB
import Testing

@testable import GentooCore

///
/// Non-ASCII strings that have to survive a round trip.
///
/// Not decoration. §17 names non-ASCII tags as a fixture case, ADR 0005 chose the FTS5
/// tokenizer for them, and a library of real music is full of them. The last entry is the
/// interesting one: `Café` written in NFD, as a `e` followed by a combining acute accent
/// rather than a single precomposed character. macOS filesystems hand back NFD routinely, and
/// a layer that quietly normalizes it would make a stored string stop comparing equal to the
/// one that was written.
///
private enum NonASCII {
    static let artist = "Björk"
    static let title = "Jóga"
    static let japanese = "坂本龍一"
    static let icelandic = "Þeir Sem Elska Ekki"
    static let decomposed = "Cafe\u{0301} Tacvba"
}

///
/// Every §5 record type survives a write and a read (#6).
///
/// Two failures are worth catching here and nowhere else. A property whose name does not map
/// onto its column — `camelCase` to `snake_case` is done by strategy rather than by hand, so
/// a mismatch is possible and would otherwise surface as a confusing SQL error deep in M4.
/// And a value that changes on the way through: an enum stored as something other than the
/// text §5 documents, or a string that comes back normalized.
///
@Suite("Model round trips")
struct ModelRoundTripTests {
    ///
    /// Column mapping
    ///

    @Test("Every record encodes exactly its table's columns")
    func recordColumnsMatchTables() throws {
        let problems = try TestDatabase.withMigratedDatabase { db -> [String] in
            // Compared against the migrated database rather than against a second
            // transcription of §5: the migration is already held to §5 by InitialSchemaTests,
            // so matching the built table matches the spec, transitively and without a third
            // copy of the column list to keep in sync.
            try [
                mismatch(Root(path: "/Music"), db),
                mismatch(File(rootID: 1, path: "/a.flac", size: 1, mtime: 1, format: .flac, lastSeenAt: 0), db),
                mismatch(Track(audioHash: "h", addedAt: 0), db),
                mismatch(Album(albumKey: "k"), db),
                mismatch(Artist(name: "n"), db),
                mismatch(Artwork(sha256: "s", source: .embedded), db),
                mismatch(Sublibrary(name: "n", ruleJSON: "{}", position: 0, createdAt: 0), db),
                mismatch(TrackCollection(name: "n", createdAt: 0), db),
                mismatch(CollectionItem(collectionID: 1, trackID: 1, position: 1024), db),
                mismatch(Queue(name: "n", createdAt: 0), db),
                mismatch(QueueItem(queueID: 1, trackID: 1, position: 1024), db),
                mismatch(PlayHistory(trackID: 1, playedAt: 0, msPlayed: 0, completed: true), db),
            ].compactMap { $0 }
        }

        #expect(problems.isEmpty)
    }

    ///
    /// Fully populated
    ///

    @Test("Every record round-trips with every column populated")
    func fullyPopulatedRecordsRoundTrip() throws {
        try TestDatabase.withMigratedDatabase { db in
            var root = Root(
                path: "/Volumes/Music/\(NonASCII.artist)",
                bookmark: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                enabled: false,
                lastFullScanAt: 1_700_000_000
            )
            try root.insert(db)

            var artwork = Artwork(
                sha256: String(repeating: "a", count: 64),
                source: .sidecar,
                width: 1400,
                height: 1400,
                pathThumb: "/Caches/\(NonASCII.japanese)/thumb@2x.heic",
                pathMedium: "/Caches/medium@2x.heic",
                pathFull: "/Caches/full.heic"
            )
            try artwork.insert(db)

            var album = Album(
                albumKey: "björk|homogenic|1997",
                title: "Homogenic",
                albumArtist: NonASCII.artist,
                albumArtistSort: "Bjork",
                year: 1997,
                discCount: 2,
                isCompilation: true,
                artworkID: artwork.id,
                musicbrainzReleaseID: "9f4a2d1e-0000-4000-8000-000000000001"
            )
            try album.insert(db)

            var artist = Artist(name: NonASCII.artist, sortName: "Bjork, \(NonASCII.icelandic)")
            try artist.insert(db)

            // Inserted before the track, with a nil trackID: files and tracks reference each
            // other, so one of the two links is always set on a second pass.
            var file = File(
                rootID: root.id!,
                path: "/Volumes/Music/\(NonASCII.artist)/\(NonASCII.title).flac",
                size: 41_231_996,
                mtime: 1_699_999_999,
                format: .flac,
                audioHash: String(repeating: "f", count: 32),
                sampleRate: 44_100,
                channels: 2,
                bitDepth: 16,
                bitrate: 1_411,
                durationMs: 303_000,
                scanState: .error,
                scanError: "STREAMINFO MD5 was zeroed",
                lastSeenAt: 1_700_000_000
            )
            try file.insert(db)

            var track = Track(
                audioHash: String(repeating: "f", count: 32),
                preferredFileID: file.id,
                albumID: album.id,
                title: NonASCII.title,
                artist: NonASCII.artist,
                artistSort: "Bjork",
                albumArtist: NonASCII.decomposed,
                trackNo: 4,
                discNo: 2,
                year: 1997,
                genre: "Electronic",
                durationMs: 303_000,
                musicbrainzTrackID: "9f4a2d1e-0000-4000-8000-000000000002",
                addedAt: 1_700_000_001,
                playCount: 17,
                lastPlayedAt: 1_700_000_500,
                rating: 5
            )
            try track.insert(db)

            file.trackID = track.id
            try file.update(db)

            var sublibrary = Sublibrary(
                name: "Vinyl Rips — \(NonASCII.japanese)",
                ruleJSON: #"{"match":"all","rules":[{"field":"genre","op":"equals","value":"Jazz"}]}"#,
                position: 2048,
                createdAt: 1_700_000_002
            )
            try sublibrary.insert(db)

            var collection = TrackCollection(name: "Late Night \(NonASCII.decomposed)", createdAt: 1_700_000_003)
            try collection.insert(db)

            let collectionItem = CollectionItem(collectionID: collection.id!, trackID: track.id!, position: 1024)
            try collectionItem.insert(db)

            var queue = Queue(
                name: "Up Next \(NonASCII.icelandic)",
                isActive: true,
                shuffleEnabled: true,
                repeatMode: .one,
                createdAt: 1_700_000_004
            )
            try queue.insert(db)

            let queueItem = QueueItem(queueID: queue.id!, trackID: track.id!, position: 1024, shufflePosition: 3072)
            try queueItem.insert(db)

            var history = PlayHistory(trackID: track.id!, playedAt: 1_700_000_500, msPlayed: 303_000, completed: true)
            try history.insert(db)

            #expect(try Root.fetchOne(db, key: root.id!) == root)
            #expect(try Artwork.fetchOne(db, key: artwork.id!) == artwork)
            #expect(try Album.fetchOne(db, key: album.id!) == album)
            #expect(try Artist.fetchOne(db, key: artist.id!) == artist)
            #expect(try File.fetchOne(db, key: file.id!) == file)
            #expect(try Track.fetchOne(db, key: track.id!) == track)
            #expect(try Sublibrary.fetchOne(db, key: sublibrary.id!) == sublibrary)
            #expect(try TrackCollection.fetchOne(db, key: collection.id!) == collection)
            #expect(try Queue.fetchOne(db, key: queue.id!) == queue)
            #expect(try PlayHistory.fetchOne(db, key: history.id!) == history)
            #expect(try CollectionItem.fetchAll(db) == [collectionItem])
            #expect(try QueueItem.fetchAll(db) == [queueItem])
        }
    }

    ///
    /// Nullable columns
    ///

    @Test("Every record round-trips with every nullable column left nil")
    func minimalRecordsRoundTrip() throws {
        try TestDatabase.withMigratedDatabase { db in
            // The other half of the round trip. A record that only ever gets tested fully
            // populated will not catch a non-optional Swift property sitting over a nullable
            // column — it decodes fine right up until it meets a real library, where a file
            // with no title is entirely normal.
            var root = Root(path: "/Music")
            try root.insert(db)

            var artwork = Artwork(sha256: "bare", source: .embedded)
            try artwork.insert(db)

            var album = Album(albumKey: "bare")
            try album.insert(db)

            var artist = Artist(name: "bare")
            try artist.insert(db)

            var file = File(rootID: root.id!, path: "/Music/a.wav", size: 1, mtime: 1, format: .wav, lastSeenAt: 0)
            try file.insert(db)

            var track = Track(audioHash: "bare", addedAt: 0)
            try track.insert(db)

            var queue = Queue(name: "bare", createdAt: 0)
            try queue.insert(db)

            let queueItem = QueueItem(queueID: queue.id!, trackID: track.id!, position: 1024)
            try queueItem.insert(db)

            #expect(try Root.fetchOne(db, key: root.id!) == root)
            #expect(try Artwork.fetchOne(db, key: artwork.id!) == artwork)
            #expect(try Album.fetchOne(db, key: album.id!) == album)
            #expect(try Artist.fetchOne(db, key: artist.id!) == artist)
            #expect(try File.fetchOne(db, key: file.id!) == file)
            #expect(try Track.fetchOne(db, key: track.id!) == track)
            #expect(try Queue.fetchOne(db, key: queue.id!) == queue)
            #expect(try QueueItem.fetchAll(db) == [queueItem])

            // Spot-check that these really are NULL in the database and not an empty string
            // or a zero that happens to decode back to nil.
            let nulls = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM tracks
                    WHERE title IS NULL AND artist IS NULL AND album_id IS NULL
                      AND rating IS NULL AND last_played_at IS NULL
                    """
            )
            #expect(nulls == 1)
        }
    }

    ///
    /// Enum-backed columns
    ///

    @Test("Every AudioFormat case round-trips as the text §5 documents", arguments: AudioFormat.allCases)
    func audioFormatRoundTrips(_ format: AudioFormat) throws {
        try TestDatabase.withMigratedDatabase { db in
            var root = Root(path: "/Music")
            try root.insert(db)

            var file = File(
                rootID: root.id!,
                path: "/Music/a.\(format.rawValue)",
                size: 1,
                mtime: 1,
                format: format,
                lastSeenAt: 0
            )
            try file.insert(db)

            let fetched = try File.fetchOne(db, key: file.id!)
            let stored = try String.fetchOne(db, sql: "SELECT format FROM files WHERE id = ?", arguments: [file.id!])

            #expect(fetched?.format == format)
            // The stored text matters beyond the round trip: the rules engine compiles
            // `format` predicates to SQL against these literals (§7).
            #expect(stored == format.rawValue)
        }
    }

    @Test("Every ScanState case round-trips as the text §5 documents", arguments: ScanState.allCases)
    func scanStateRoundTrips(_ state: ScanState) throws {
        try TestDatabase.withMigratedDatabase { db in
            var root = Root(path: "/Music")
            try root.insert(db)

            var file = File(
                rootID: root.id!,
                path: "/Music/a.flac",
                size: 1,
                mtime: 1,
                format: .flac,
                scanState: state,
                lastSeenAt: 0
            )
            try file.insert(db)

            let fetched = try File.fetchOne(db, key: file.id!)
            let stored = try String.fetchOne(db, sql: "SELECT scan_state FROM files WHERE id = ?", arguments: [file.id!])

            #expect(fetched?.scanState == state)
            #expect(stored == state.rawValue)
        }
    }

    @Test("Every ArtworkSource case round-trips as the text §5 documents", arguments: ArtworkSource.allCases)
    func artworkSourceRoundTrips(_ source: ArtworkSource) throws {
        try TestDatabase.withMigratedDatabase { db in
            var artwork = Artwork(sha256: source.rawValue, source: source)
            try artwork.insert(db)

            let fetched = try Artwork.fetchOne(db, key: artwork.id!)
            let stored = try String.fetchOne(db, sql: "SELECT source FROM artwork WHERE id = ?", arguments: [artwork.id!])

            #expect(fetched?.source == source)
            #expect(stored == source.rawValue)
        }
    }

    @Test("Every RepeatMode case round-trips as the text §8 documents", arguments: RepeatMode.allCases)
    func repeatModeRoundTrips(_ mode: RepeatMode) throws {
        try TestDatabase.withMigratedDatabase { db in
            var queue = Queue(name: mode.rawValue, repeatMode: mode, createdAt: 0)
            try queue.insert(db)

            let fetched = try Queue.fetchOne(db, key: queue.id!)
            let stored = try String.fetchOne(db, sql: "SELECT repeat_mode FROM queues WHERE id = ?", arguments: [queue.id!])

            #expect(fetched?.repeatMode == mode)
            #expect(stored == mode.rawValue)
        }
    }

    @Test("A queue's default repeat mode decodes as off")
    func defaultRepeatModeDecodes() throws {
        try TestDatabase.withMigratedDatabase { db in
            // Inserted as raw SQL so the column default does the work rather than the Swift
            // default. ADR 0011 puts 'off' in the schema; this proves the enum can read it.
            try db.execute(sql: "INSERT INTO queues (id, name, created_at) VALUES (1, 'Up Next', 0)")

            let queue = try Queue.fetchOne(db, key: 1)

            #expect(queue?.repeatMode == .off)
            #expect(queue?.shuffleEnabled == false)
            #expect(queue?.isActive == false)
        }
    }

    ///
    /// Identity
    ///

    @Test("Inserting assigns the row id back onto the record")
    func insertAssignsRowID() throws {
        try TestDatabase.withMigratedDatabase { db in
            var first = Artist(name: "First")
            var second = Artist(name: "Second")

            try first.insert(db)
            try second.insert(db)

            #expect(first.id != nil)
            #expect(second.id != nil)
            #expect(first.id != second.id)
        }
    }

    @Test("Updating a fetched record writes back through the same columns")
    func updateRoundTrips() throws {
        try TestDatabase.withMigratedDatabase { db in
            var track = Track(audioHash: "h", addedAt: 0)
            try track.insert(db)

            // An update encodes every column, so a mapping that only works on insert would
            // surface here.
            track.title = NonASCII.title
            track.rating = 4
            track.playCount = 9
            try track.update(db)

            #expect(try Track.fetchOne(db, key: track.id!) == track)
        }
    }
}

///
/// Returns a description of how `record`'s encoded columns differ from its table's, or nil if
/// they match.
///
private func mismatch<R: LibraryRecord>(_ record: R, _ db: Database) throws -> String? {
    let encoded = Set(try record.databaseDictionary.keys)
    let actual = Set(try db.columns(in: R.databaseTableName).map(\.name))

    guard encoded != actual else { return nil }

    return """
        \(R.databaseTableName): \
        record encodes \(encoded.subtracting(actual).sorted()) which the table lacks; \
        table has \(actual.subtracting(encoded).sorted()) which the record omits
        """
}
