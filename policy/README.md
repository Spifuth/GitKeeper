# policy/

Branch protection for every public repository on this account, as a file rather
than as a memory of which boxes were ticked in a web UI.

    ./apply-rulesets.sh            # show what would change, write nothing
    ./apply-rulesets.sh --apply    # create or update the rulesets
    ./apply-rulesets.sh --verify   # report the live state, non-zero if it drifted

Needs `gh` (authenticated) and `jq`.

## What it applies

One ruleset per protected branch, named `protected-<branch>`, identical
everywhere:

| Rule | Effect |
|---|---|
| `deletion` | the branch cannot be deleted |
| `non_fast_forward` | no force-push |
| `pull_request` | no direct push; changes arrive through a pull request |
| `required_status_checks` | the branch's CI must be green |

**`bypass_actors` is empty.** The rules apply to the owner exactly as they apply
to a contributor.

That is only workable because `required_approving_review_count` is **0**. With a
single collaborator, GitHub forbids approving your own pull request, so any
non-zero count makes the rule unsatisfiable and forces a bypass on every single
merge — which is how a branch protection ends up real for everybody except the
person it was configured by. The guarantee that nobody merges in your place is
not the review count; it is that nobody else has write access.

## Why one ruleset per branch

A ruleset applies one set of rules to every ref it covers, so `main` and `dev`
cannot require different checks inside a single one — and they routinely need
to, because a CI trigger often lists one branch and not the other.

## The failure this exists to prevent

A required status check is matched by **context name**. Require a context that
never reports on that branch — a release job, a renamed job, a workflow whose
`pull_request:` trigger does not list the branch — and every pull request to it
becomes permanently unmergeable. GitHub shows *"Expected — Waiting for status to
be reported"*. There is no error, no failing job, nothing in the audit log: the
repository simply stops accepting merges, and the configuration that did it
looks entirely correct.

So `checks` in `policy.json` is a **target**, and a context is only required
once there is evidence for it:

- **tier 1** — a pull request targeting that branch has actually reported it.
- **tier 2** — the branch carries a dated `verified` note: a human read the
  workflow trigger and confirmed it covers *that* branch.

Anything with neither is withheld and printed. Withholding is the safe direction
to be wrong in: an unprotected branch is visible, a deadlocked one is not.

Evidence is read from pull requests, never from the tip of the branch. A
repository whose CI triggers on pushes to `dev` has no check at all on the tip
of `main` — main only ever receives merges — while pull requests into main are
checked perfectly well. A required check is a promise about pull requests, so
the evidence has to come from pull requests.

## Editing the policy

`policy.json` is the source of truth. Add a repository, add a branch, change a
check list, then run `--apply`. It is idempotent: an existing ruleset with the
same name is updated in place, so its id survives.

After changing a CI trigger, re-run — a check withheld last time may have become
requireable.
