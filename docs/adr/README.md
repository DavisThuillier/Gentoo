# Architecture Decision Records

Each record captures one decision, the context that forced it, and the alternatives
rejected in reaching it. Records are immutable once accepted: to change a decision, add a
new record that supersedes the old one and update the old record's status. Never rewrite
history here.

Records 0001–0007 are backfilled from [the spec](../spec.md) — they document decisions
made during design rather than after. They exist so that settled questions are not
relitigated, and so the reasoning survives beyond the memory of whoever made the call.

| # | Decision | Status |
|---|---|---|
| [0001](0001-client-server-process-split.md) | Split playback into a bundled XPC service | Accepted |
| [0002](0002-sfbaudioengine-for-playback-and-tag-io.md) | SFBAudioEngine for both playback and tag I/O | Accepted |
| [0003](0003-native-swiftui-appkit-ui.md) | Native SwiftUI with AppKit where required | Accepted |
| [0004](0004-metadata-first-identity-without-decoding.md) | Metadata-first identity via byte-level hashing | Accepted |
| [0005](0005-sqlite-via-grdb.md) | SQLite via GRDB, with FTS5 for search | Accepted |
| [0006](0006-rules-engine-as-standalone-component.md) | Rules engine as a standalone, uncoupled component | Accepted |
| [0007](0007-tag-edits-write-to-all-backing-files.md) | Tag edits write to every backing file, atomically | Accepted |
| [0008](0008-core-first-swiftpm-package.md) | Build the testable core as a SwiftPM package first | Accepted |
| [0009](0009-squash-merged-pull-requests-on-linear-main.md) | Land work on main via squash-merged pull requests | Accepted |
| [0010](0010-defer-release-branches.md) | Defer release and integration branches | Accepted |

## Format

Use [0000-template.md](0000-template.md). Keep records short — a page is plenty. The
value is in the *Context* and *Alternatives considered* sections; a decision without its
rejected alternatives is just an assertion.

Numbering is sequential and never reused. Add records in commits scoped `docs(adr)`.
