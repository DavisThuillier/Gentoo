import GRDB

///
/// One audio file on disk (§5, §6).
///
/// **A file is not a track.** Several bit-identical files collapse into one `Track` through a
/// shared `audioHash`, and `trackID` is the link. Paths are not identity: a file moves, exists
/// in two roots at once, and is re-read when `size` or `mtime` changes.
///
/// `audioHash` is nullable because a file exists in the database before it has been hashed —
/// and stays that way if hashing failed, alongside a `scanState` of `error`.
///
public struct File: IdentifiedRecord, Equatable {
    public static let databaseTableName = "files"

    public enum CodingKeys: String, CodingKey {
        case id
        case rootID = "root_id"
        case trackID = "track_id"
        case path
        case size
        case mtime
        case format
        case audioHash = "audio_hash"
        case sampleRate = "sample_rate"
        case channels
        case bitDepth = "bit_depth"
        case bitrate
        case durationMs = "duration_ms"
        case scanState = "scan_state"
        case scanError = "scan_error"
        case lastSeenAt = "last_seen_at"
    }

    public var id: Int64?
    public var rootID: Int64
    public var trackID: Int64?
    public var path: String
    public var size: Int64
    /// Unix epoch seconds. With `size`, decides whether an incremental scan re-reads the file.
    public var mtime: Int64
    public var format: AudioFormat
    /// Computed from bytes only, never by decoding (§6).
    public var audioHash: String?
    public var sampleRate: Int?
    public var channels: Int?
    public var bitDepth: Int?
    public var bitrate: Int?
    public var durationMs: Int?
    public var scanState: ScanState
    public var scanError: String?
    /// Unix epoch seconds.
    public var lastSeenAt: Int64

    public init(
        id: Int64? = nil,
        rootID: Int64,
        trackID: Int64? = nil,
        path: String,
        size: Int64,
        mtime: Int64,
        format: AudioFormat,
        audioHash: String? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil,
        bitDepth: Int? = nil,
        bitrate: Int? = nil,
        durationMs: Int? = nil,
        scanState: ScanState = .ok,
        scanError: String? = nil,
        lastSeenAt: Int64
    ) {
        self.id = id
        self.rootID = rootID
        self.trackID = trackID
        self.path = path
        self.size = size
        self.mtime = mtime
        self.format = format
        self.audioHash = audioHash
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.bitrate = bitrate
        self.durationMs = durationMs
        self.scanState = scanState
        self.scanError = scanError
        self.lastSeenAt = lastSeenAt
    }
}
