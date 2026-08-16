# 0008. Build the testable core as a SwiftPM package before the Xcode app

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §17

## Context

Spec §17 calls for a single Xcode project with two targets — app and XPC service — plus a
shared framework for models and the rules engine. It also requires that the rules engine,
scanner, and identity hashing be unit-testable without a UI.

Producing a `.app` bundle with an embedded XPC service, entitlements, App Sandbox, and
codesigning requires a full Xcode installation. Profiling against the §15 performance
budget requires Instruments, which also ships with Xcode.

The bulk of the load-bearing logic — schema and migrations, rule compilation, `audio_hash`
computation, album grouping — needs none of that. It is pure Swift over SQLite and file
bytes.

## Decision

Build the shared core as a standalone SwiftPM package, developed and tested with
`swift build` / `swift test`. The Xcode project consumes it as a local package dependency
once the app shell is needed.

**The core package must not import SwiftUI or AppKit.** If a type needs a UI framework, it
belongs in the app target.

## Consequences

- Work on the highest-risk, most testable logic starts immediately, with no Xcode
  installation on the critical path.
- The §17 requirement that the engine, scanner, and hashing be UI-testable becomes
  structurally enforced rather than a convention someone has to remember — a UI import in
  the core is a compile error, not a code review note.
- The [0006](0006-rules-engine-as-standalone-component.md) decoupling requirement is
  likewise enforced by the module boundary.
- `swift test` is fast and scriptable in CI without a macOS runner carrying a full Xcode
  image, though a macOS runner is still eventually needed for the app targets.
- Xcode 26.x is still required before the app, XPC service, App Sandbox, security-scoped
  bookmarks, or any Instruments profiling can happen. The toolchain must match the
  installed Swift version to avoid skew.
- The package boundary must be drawn correctly on the first pass. Moving a type across it
  later is cheap; discovering that the boundary is in the wrong place is not.

## Alternatives considered

**Scaffold the full Xcode project first, then fill it in.** Matches the §17 description
directly. Rejected only on sequencing: it puts an Xcode install on the critical path for
work that does not need it, and it makes the UI-independence requirement a convention
rather than a constraint the compiler enforces.

**Keep everything in the Xcode project with no separate package.** Fewer moving parts.
Rejected because nothing then prevents the scanner or rules engine from acquiring a UI
dependency, and §17 requires that they not have one.

**Build the core as a package and never adopt Xcode.** SwiftPM alone cannot produce a
`.app` bundle with an embedded XPC service, handle entitlements and codesigning, or provide
Instruments. Not viable for this product.
