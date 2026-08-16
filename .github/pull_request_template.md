<!--
The PR title becomes the commit subject on main under squash merge.
It must be a valid Conventional Commit: <type>(<scope>): <subject>
CI enforces this.
-->

## Summary

What changed and why. The why matters more.

## Spec and ADR references

Sections of `docs/spec.md` this touches, and any ADR it implements or affects.
If it contradicts a settled decision, say so explicitly and explain what changed.

## Verification

How this was checked. Tests added, manual steps taken, or measurements made.

## Performance

Delete if not applicable. If this touches scanning, the album grid, search, or memory,
state which §15 budget it affects and what was measured — not what was assumed.

## Checklist

- [ ] Schema changes ship with a versioned migration in this PR
- [ ] New library queries thread the sublibrary predicate
- [ ] No rule value is string-interpolated into SQL
- [ ] Core package imports no SwiftUI or AppKit (`Scripts/check-no-ui-imports.sh`)
- [ ] `audio_hash` is unchanged by any tag-write path touched here
