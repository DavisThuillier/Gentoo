# 0003. Build the UI natively in SwiftUI, dropping to AppKit where required

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §12

## Context

UI polish is priority #1 and large-library performance is priority #2 (§1). The app is
macOS-only. It needs a native menu bar, system keyboard handling, Finder integration, and
Now Playing / media key support.

SwiftUI gives the fastest path to a polished, art-forward interface. It does not hold
60fps on flat lists of tens of thousands of rows, which the search results view requires
over a 50k-track library.

## Decision

SwiftUI throughout, with AppKit where the platform demands it:

- **Search results list — AppKit is mandatory.** Use `NSTableView` via
  `NSViewRepresentable`. SwiftUI `List` and `Table` will not sustain 60fps at this scale.
- **Drag-and-drop reordering** in queues and collections drops to AppKit if SwiftUI's
  `onMove` proves insufficient for the interaction quality wanted.
- **The album grid starts as SwiftUI `LazyVGrid`** and moves to `NSCollectionView` only if
  it fails to hold frame rate. Measure before deciding.

## Consequences

- Two UI paradigms coexist, and the boundary between them must be deliberate. Bridged
  views need explicit ownership of their data source and update path.
- The "measure before deciding" clause on the album grid is a real commitment: it requires
  profiling against the §15 targets with a realistic library, not a guess.
- Native menu bar, keyboard handling, Finder integration, and Now Playing come for free
  rather than being reimplemented.
- No web toolchain, no bundler, no JavaScript runtime in the product.

## Alternatives considered

**Tauri, Electron, or any web UI.** Faster iteration on visual design. Rejected because it
trades away the native menu bar, system keyboard handling, Finder integration, and Now
Playing — and iteration speed is not a stated goal, while UI polish and native feel are
priority #1.

**Pure AppKit.** Maximum control and guaranteed performance. Rejected as disproportionate:
it would slow the entire product surface to buy performance that is only needed in one
view, against priority #3.

**Pure SwiftUI, accepting list performance.** Rejected because it fails priority #2
directly and visibly, in the one view most likely to be used on a large library.
