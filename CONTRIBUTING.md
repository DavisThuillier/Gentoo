# Contributing

## Setup

Enable the commit message hook once per clone:

```sh
git config core.hooksPath .githooks
```

It is not installed automatically — git will not run hooks from a tracked directory without
being told to, and silently executing checked-in scripts on clone would be a poor default.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

Body explaining why, wrapped at 72 characters.

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Types**

| | |
|---|---|
| `feat` | A user-visible capability |
| `fix` | A bug fix |
| `perf` | A change made for performance, with a measurement in the body |
| `refactor` | Restructuring with no behavior change |
| `docs` | Documentation, including the spec and ADRs |
| `test` | Tests and fixtures |
| `build` | Build system, SwiftPM, Xcode project configuration |
| `ci` | CI configuration and workflows |
| `chore` | Tooling and housekeeping |
| `revert` | Reverting a previous commit |

**Scopes**

`library` `scanner` `identity` `playback` `xpc` `rules` `queue` `collections` `artwork`
`ui` `search` `tags` `db` `build` `adr` `claude` `deps` `release`

Scope is optional but preferred. Add new scopes to `.githooks/commit-msg` in the same
commit that first uses them.

**Rules**

- Subject in the imperative mood: "add", not "added" or "adds"
- No trailing period
- 72 characters or fewer
- The body explains **why**. The diff already shows what
- Cite the spec section or ADR the change implements
- Breaking changes take `!` after the scope and a `BREAKING CHANGE:` footer

Commits produced with AI assistance carry a `Co-Authored-By: Claude <noreply@anthropic.com>`
trailer. See the Development section of the [README](README.md).

## Branches and merging

Work happens on short-lived branches off `main`:

```
feat/rules-engine
fix/flac-md5-fallback
docs/adr-replaygain
```

Branches land via **squash-merged pull request**. Commits on a branch may be messy — they
are squashed away. The **PR title becomes the commit subject on `main`**, so it must itself
be a valid Conventional Commit. CI enforces this.

`main` stays linear. No merge commits, no force pushes, no direct pushes — GitHub rulesets
enforce this, and the bypass list is empty.

There is no `develop` branch and there are no `release/*` branches. `main` is the trunk and
releases are tagged on it. See [ADR 0009](docs/adr/0009-squash-merged-pull-requests-on-linear-main.md)
for the merge model and [ADR 0010](docs/adr/0010-defer-release-branches.md) for why release
branches are deferred — including the condition that should trigger revisiting it.

## Before opening a PR

- Schema changes ship with a versioned migration **in the same commit**
- New library queries thread the sublibrary predicate
- No rule value is string-interpolated into SQL
- The core package imports neither SwiftUI nor AppKit — `Scripts/check-no-ui-imports.sh`
  checks this, and CI runs the same script
- `audio_hash` is unchanged by any tag-write path touched
- Performance-relevant changes state what was **measured**, not assumed

## Decisions

A change that makes a real architectural choice needs an ADR. Copy
[docs/adr/0000-template.md](docs/adr/0000-template.md), take the next number, and add it to
the index in [docs/adr/README.md](docs/adr/README.md).

Records are immutable once accepted. To change a decision, write a new record that
supersedes the old one and update the old record's status — do not edit the original.

### Numbering across concurrent branches

Two branches can both claim the next number. This is expected, cheap to fix, and
**self-announcing** — you will not merge a collision by accident:

- Every ADR adds a row to the index table in `docs/adr/README.md`. Two concurrent records
  both touch it, so git raises a conflict.
- The ruleset requires branches be up to date before merging, so the conflict surfaces
  *before* the merge, not after.

**Protocol: the second branch to merge renumbers.** Rename the file, update its internal
cross-references, and fix the index row. It takes a minute and the collision cannot reach
`main`.

Numbers are never reused, even for a record that was drafted and abandoned.

Numbering stays sequential rather than date-based or issue-derived. Sequential numbers are
readable, sort correctly, and make cross-references short — `[0004]` rather than
`[2026-08-16-identity]`. That's worth more than eliminating a collision that announces
itself and takes a minute to resolve.

Several alternatives are already settled and recorded so they are not relitigated; they are
listed in [CLAUDE.md](CLAUDE.md). Reopening one is legitimate, but it requires stating what
new information changes the analysis, and a superseding ADR.

The spec's §16 lists open product questions. Answer them in the spec first, then implement
— not the other way around.
