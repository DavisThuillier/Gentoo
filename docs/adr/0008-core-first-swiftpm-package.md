# 0008. Build the testable core as a SwiftPM package before the Xcode app

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §17

## Context

Spec §17 calls for a single Xcode project with two targets — app and XPC service — plus a
shared framework for models and the rules engine. It also requires that the rules engine,
scanner, and identity hashing be unit-testable without a UI.

Xcode provides two things this project cannot practically do without: **SwiftUI Previews**,
which is the iteration loop for priority #1, and **Instruments**, without which §15's seven
numeric targets cannot be verified at all.

It provides them as tooling, not as capability. The Command Line Tools SDK contains
`SwiftUI.framework` and `AppKit.framework` with their `.swiftinterface` files, `codesign`
lives at `/usr/bin/codesign`, and `notarytool` ships with CLT — so compiling, signing,
entitling, and notarizing a macOS GUI application are all possible without Xcode. A `.app`
is a directory with an `Info.plist`; SwiftPM will not emit one, but a script will.

The bulk of the load-bearing logic — schema and migrations, rule compilation, `audio_hash`
computation, album grouping — needs neither Xcode nor a UI framework. It is pure Swift over
SQLite and file bytes.

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
- Xcode 26.x is needed before the app target, XPC service, SwiftUI Previews, or Instruments
  profiling. The toolchain must match the installed Swift version to avoid skew.
- **This does not defer UI work to the end.** Design decisions need no Xcode at all, and a
  UI prototype over synthetic data needs Xcode but nothing from this package — notably, the
  §12 `LazyVGrid` vs. `NSCollectionView` measurement depends on render density and image
  decode cost, not on real metadata. See `docs/roadmap.md`, Track D.
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

**Build the core as a package and never adopt Xcode.** Genuinely possible — the CLT SDK
compiles SwiftUI and AppKit, and `codesign` and `notarytool` handle entitlements, signing,
and notarization. Bundle assembly would be a shell script.

Rejected on cost rather than capability. It forfeits SwiftUI Previews, which is the
iteration loop for priority #1, and Instruments, without which §15's targets cannot be
verified. It also means maintaining a hand-rolled bundle-sign-notarize pipeline, which runs
against priority #3. Being off the supported path makes every future toolchain change the
project's problem rather than Apple's.

*(An earlier revision of this record claimed SwiftPM "cannot handle entitlements and
codesigning." That was factually wrong — `codesign` does both and ships with the Command
Line Tools. The decision is unchanged; the reasoning is corrected. Recorded here rather
than silently edited.)*
