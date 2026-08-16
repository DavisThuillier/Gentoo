# 0010. Defer release and integration branches until parallel version support is needed

**Status:** Accepted
**Date:** 2026-08-16

## Context

[ADR 0009](0009-squash-merged-pull-requests-on-linear-main.md) settles *how* work lands on
`main`. It does not settle the branch **topology** around it — whether there is a
long-lived `develop` integration branch, and whether releases are cut on `release/*`
branches.

The two are genuinely separable. Squash-merged PRs onto a trunk are compatible with release
branches; many projects run both.

Git Flow's `develop` branch exists to hold work that is integrated but not yet released,
and `release/*` branches exist to stabilize a version while development continues on the
next. Both solve problems that appear at a specific point: when a shipped version must be
maintained in parallel with an unshipped one.

The project is pre-v1. Distribution is a personal install initially (spec §1), there are no
users to hotfix for, and no released version to maintain.

## Decision

**No `develop` branch and no `release/*` branches for now.** `main` is the trunk; releases
are marked with tags on `main`.

**Revisit when — and only when — a shipped version must be maintained while the next is in
development.** That is the trigger. Anticipating it earlier buys nothing and costs a merge
layer on every change.

This deferral is recorded rather than left implicit precisely because deferred decisions
without a written trigger are decisions that get forgotten and then rediscovered as
confusion.

## Consequences

- One less integration step per change. Work goes branch → `main`, not branch → `develop` →
  `main`.
- `main` is always the current state of the project, with no ambiguity about whether
  `develop` or `main` is authoritative.
- **There is no path to ship a fix for a released version without also shipping everything
  merged since.** This is precisely the constraint that triggers revisiting, and it is
  invisible until the first time it bites — hence the explicit trigger above.
- Adding `release/*` branches later is **additive**, not a migration: cut a branch from the
  tag, apply fixes, merge back. Nothing about the current topology has to be undone. This
  is what makes deferral cheap.
- Any long-lived branch introduced later needs its own ruleset entry. GitHub's
  "automatically delete head branches" removes the head branch of a merged PR, so merging
  `develop` into `main` via PR would delete `develop` — **unless it is protected.**
  Protected branches are exempt from auto-deletion, so the ruleset is what makes the
  automation safe. Add the protection in the same change that adds the branch, not after.
- Version tags on `main` become the only record of what shipped, so tagging has to actually
  happen at release time.

## Alternatives considered

**Git Flow now (`develop` + `release/*` + `hotfix/*`).** Well-understood, and ready for
parallel version maintenance the day it is needed. Rejected as premature: every change pays
an extra merge, and the structure addresses a problem the project does not yet have. Its
own author has since described it as poorly suited to projects delivering continuously from
a trunk.

**A `develop` branch without `release/*`.** Keeps `main` as a "known good" pointer. Rejected
because with no released version, `main` and `develop` would be identical in practice —
duplicating a branch to express a distinction that does not yet exist.

**Long-lived `next` or version branches.** Same objection, with added ambiguity about which
branch is authoritative.

**Deciding informally and not recording it.** Rejected because the value here is almost
entirely in the recorded trigger. The decision to defer is easy; remembering *what* it was
deferred pending is the part that fails silently six months later.
