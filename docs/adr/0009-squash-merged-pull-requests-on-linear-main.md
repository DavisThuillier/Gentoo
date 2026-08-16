# 0009. Land work on main via squash-merged pull requests

**Status:** Accepted
**Date:** 2026-08-16

## Context

The project is solo, and a clean, legible commit history is an explicit goal rather than a
side effect — the history is part of what the repository demonstrates.

Working commits are not the same artifact as landed commits. Development produces
"wip", "fix typo", and "actually fix it" as a matter of course. A history that preserves
them records how the work felt rather than what it did, and is harder to read, bisect, and
review after the fact.

Conventional Commits are enforced locally by `.githooks/commit-msg`. Whatever mechanism
lands work on `main` must be the thing that convention is enforced against — a hook that
only sees branch commits guards the wrong artifact.

## Decision

Work happens on short-lived branches off `main` — `feat/rules-engine`,
`fix/flac-md5-fallback` — and lands via **squash-merged pull request**. One commit on
`main` per logical change.

`main` is linear. No merge commits, no force pushes, no branch deletion.

Because squash merge takes the **PR title** as the commit subject, **the PR title must
itself be a valid Conventional Commit.** CI validates it using the same
`.githooks/commit-msg` script that runs locally, so the two gates cannot drift.

Branch commits are unconstrained. They are squashed away and never reach `main`.

GitHub rulesets enforce this rather than convention alone: restrict deletions, block force
pushes, require linear history, require a pull request, require the PR-title status check.
Squash is the only merge method enabled. The bypass list is empty — the rules apply to the
author too.

## Consequences

- `git log --oneline` on `main` reads as a list of changes, one line each, every line a
  valid Conventional Commit.
- Bisecting is meaningful: every commit on `main` is a complete change, so no commit is a
  broken intermediate state.
- Reverting a feature is one revert, not a range.
- **The commit body must be written at merge time**, in the merge box, not accumulated
  from branch commits. This is the last editable moment before it is permanent, and it is
  easy to skip — a squash with an empty body loses the "why" the convention exists to
  capture.
- The granular development history is discarded. For work where the intermediate steps are
  themselves the interesting record — a tricky bisect, a documented sequence of failed
  approaches — that reasoning has to go into the body or an ADR, because the commits will
  not survive to carry it.
- Every change requires a PR, including one-line fixes. With an empty bypass list this
  applies to the sole author. Accepted deliberately: an escape hatch granted to oneself
  makes the enforcement decorative.
- Head branches are safe to auto-delete, since their commits no longer exist in that shape
  on `main`. Protected branches are exempt from auto-deletion, which is what makes the
  setting safe to leave on if long-lived branches are ever introduced
  ([0010](0010-defer-release-branches.md)).

## Alternatives considered

**Rebase merge.** Each branch commit lands individually on `main`, preserving granular
steps while staying linear. Rejected because it makes every branch commit permanent and
therefore subject to the same quality bar — which in practice means either rewriting
history on every branch before merge, or accepting "fix typo" on `main`. Squash moves that
cleanup to a single deliberate step.

**Merge commits.** Preserves the true shape of development, and the merge commit is a
natural place to describe the change as a whole. Rejected: it produces a non-linear history
whose value is proportional to the number of concurrent contributors, which here is one.

**Direct commits to `main`.** No PR overhead, fastest for a solo developer. Rejected on two
grounds: it leaves no review surface at all, and it removes the PR-title check that is the
only enforcement point for the convention on the commits that actually matter.

**Requiring approvals on PRs.** Rejected as unworkable rather than undesirable — GitHub
does not permit self-approval, so any nonzero requirement would block the sole author
permanently. Set to zero, with the status check carrying the enforcement instead.
