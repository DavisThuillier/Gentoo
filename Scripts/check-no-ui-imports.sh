#!/bin/sh
###
### check-no-ui-imports.sh — the core package imports no UI framework
###
### ADR 0008 draws the package boundary at "needs a UI framework": a type that
### does belongs in the app target, not here. Spec §17 depends on the same line
### holding, since the rules engine, scanner, and identity hashing are required
### to be unit-testable without a UI.
###
### The Command Line Tools SDK ships SwiftUI.framework and AppKit.framework, so
### `import SwiftUI` in the core compiles perfectly well. Nothing structural
### stops it. This script is that missing structure.
###
### Run from anywhere:
###     Scripts/check-no-ui-imports.sh
###
### CI runs this exact script, so the local gate and the remote gate cannot
### drift apart. See .github/workflows/core-boundary.yml.
###

set -eu

###
### Configuration
###

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SEARCH_DIR="$ROOT/Sources"

### Cocoa is on the list because importing it imports AppKit. Leaving it off
### would let the constraint be sidestepped by spelling it differently.
FORBIDDEN='SwiftUI|SwiftUICore|AppKit|Cocoa'

### An import declaration, not the words in a sentence.
###
### Covers attributes (`@testable`, `@preconcurrency`, `@_exported`), the
### submodule form (`import AppKit.NSView`), and the rarely used kind form
### (`import struct SwiftUI.Color`). Leading `//` fails the anchor, so prose
### mentioning an import is not a match — a line inside a block comment still
### would be, which is a false positive worth accepting for a check this cheap.
PATTERN="^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)*import[[:space:]]+([[:alpha:]]+[[:space:]]+)?($FORBIDDEN)([.[:space:]]*$|[.[:space:]])"

###
### Search
###

[ -d "$SEARCH_DIR" ] || {
    printf '\n  check-no-ui-imports: no Sources directory at %s\n\n' "$SEARCH_DIR" >&2
    exit 1
}

### -r on a `find` list rather than a recursive grep: portable across the BSD
### grep on a developer's Mac and the GNU grep on the CI runner.
VIOLATIONS=$(
    find "$SEARCH_DIR" -type f -name '*.swift' -print0 \
        | xargs -0 grep -nE "$PATTERN" /dev/null \
        || true
)

###
### Reporting
###

if [ -n "$VIOLATIONS" ]; then
    printf '\n  check-no-ui-imports: the core package imports a UI framework\n\n' >&2
    printf '%s\n' "$VIOLATIONS" | sed "s|^$ROOT/|    |" >&2
    printf '\n  GentooCore must not import: %s\n\n' "$(printf '%s' "$FORBIDDEN" | tr '|' ' ')" >&2
    printf '  A type that needs a UI framework belongs in the app target, not\n' >&2
    printf '  the core package. See docs/adr/0008-core-first-swiftpm-package.md\n' >&2
    printf '  and spec §17.\n\n' >&2
    exit 1
fi

printf 'check-no-ui-imports: clean\n'
exit 0
