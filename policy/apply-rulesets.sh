#!/usr/bin/env bash
#
# Applies policy/policy.json as GitHub rulesets, one per protected branch.
#
# Dry run by default. Nothing is written without --apply.
#
#   ./policy/apply-rulesets.sh            # show what would change
#   ./policy/apply-rulesets.sh --apply    # create or update the rulesets
#   ./policy/apply-rulesets.sh --verify   # report the live state and exit
#
# THE FAILURE THIS SCRIPT EXISTS TO PREVENT
#
# A required status check is matched by *context name*. Require a context that
# never reports on that branch — a release job, a renamed job, a workflow whose
# `pull_request:` trigger does not list the branch — and every pull request to
# it becomes permanently unmergeable. GitHub shows "Expected — Waiting for
# status to be reported" and there is no error anywhere: the repository simply
# stops accepting merges, and the config that did it looks correct.
#
# So a context is only required when there is evidence for it:
#
#   first, always: a workflow on one of this repository's protected branches
#   declares the job. Observing that a context can report on some pull request
#   is not evidence that it will report on the next one — a job added by an
#   unmerged pull request reports on that pull request and nowhere else. This
#   condition is not optional; the first version of this script omitted it and
#   deadlocked GitKeeper's own PR #5.
#
#   then one of:
#   tier 1  a pull request targeting that branch has actually reported it
#   tier 2  the branch carries a dated `verified` note in policy.json — a human
#           read the workflow trigger and confirmed it covers THAT branch
#
# Neither: the check is withheld and printed. Withholding is the safe direction
# to be wrong in — an unprotected branch is visible, a deadlocked one is not.

set -uo pipefail

readonly OWNER="Spifuth"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly POLICY="$SCRIPT_DIR/policy.json"

MODE="dry-run"
case "${1:-}" in
    --apply)  MODE="apply" ;;
    --verify) MODE="verify" ;;
    "")       MODE="dry-run" ;;
    *) echo "usage: $0 [--apply|--verify]" >&2; exit 2 ;;
esac

for tool in gh jq; do
    command -v "$tool" >/dev/null || { echo "error: $tool is required" >&2; exit 1; }
done
[[ -f "$POLICY" ]] || { echo "error: $POLICY not found" >&2; exit 1; }

# Contexts observed on pull requests that TARGET $2 in $1.
#
# Deliberately not "check-runs on the tip of the branch": a repository whose CI
# triggers on pushes to dev has no check at all on the tip of main — main only
# ever receives merges — while pull requests into main are checked perfectly
# well. A required check is a promise about pull requests, so the evidence has
# to come from pull requests.
observed_checks() {
    local repo="$1" branch="$2" shas sha
    shas="$(gh pr list --repo "$OWNER/$repo" --base "$branch" --state all --limit 10 \
              --json headRefOid --jq '.[].headRefOid' 2>/dev/null)" || return 0
    [[ -n "$shas" ]] || return 0
    while IFS= read -r sha; do
        [[ -z "$sha" ]] && continue
        gh api "repos/$OWNER/$repo/commits/$sha/check-runs?per_page=100" \
            --jq '.check_runs[].name' 2>/dev/null
    done <<< "$shas" | sort -u
}

# True when any branch this repository protects declares a job producing $2.
#
# THIS FUNCTION EXISTS BECAUSE THE FIRST VERSION OF THIS SCRIPT SHIPPED THE
# DEADLOCK IT WAS WRITTEN TO PREVENT.
#
# The evidence rule used to be "a pull request targeting this branch reported
# this context". GitKeeper's `tests` job satisfied it — reported by PR #4, the
# pull request that *introduced* the job. `tests` was therefore required on
# main while the job existed nowhere but inside that one unmerged branch, and
# the next pull request, cut before #4 landed, hung on a check that could never
# report. Observing that a context CAN report on some pull request is not
# evidence that it WILL report on the next one.
#
# Why "any protected branch" and not "the base branch". A `pull_request` run
# uses the workflow files of the MERGE of head into base, not of base alone. So
# a repository whose `main` predates its CI — brutalist-lycee and FenrirBot
# both do, `main` there has no workflow directory at all — still runs the jobs
# perfectly well on a pull request from `dev`, because the merge commit carries
# dev's workflow. Grepping the base alone withholds those wrongly.
#
# Residual risk, stated rather than papered over: a pull request opened from a
# branch cut before the job existed still deadlocks, because the merge commit
# will not contain it either. That is unknowable when the ruleset is written.
# The cure is `--verify` plus merging your open pull requests, not a cleverer
# prediction.
#
# A grep rather than a YAML parser on purpose: the question is only "does this
# repository know about this job", and a parser wrong in a subtle way would be
# worse than one line of grep.
declared_in_repo() {
    local repo="$1" context="$2" branch wf body pattern
    pattern="$(printf '%s' "$context" | sed 's/[][\.*^$/]/\\&/g')"
    for branch in $(jq -r --arg r "$repo" '.repos[$r].branches | keys[]' "$POLICY"); do
        for wf in $(gh api "repos/$OWNER/$repo/actions/workflows" \
                      --jq '.workflows[]? | select(.state=="active") | .path' 2>/dev/null); do
            body="$(gh api "repos/$OWNER/$repo/contents/$wf?ref=$branch" --jq '.content' 2>/dev/null \
                     | base64 -d 2>/dev/null)" || continue
            # Either the job id (`  tests:`) or its display name (`name: CI Summary`).
            if grep -qE "^[[:space:]]{2}${pattern}:" <<< "$body" \
               || grep -qF "name: $context" <<< "$body"; then
                return 0
            fi
        done
    done
    return 1
}

ruleset_id_named() {
    gh api "repos/$OWNER/$1/rulesets" \
        --jq ".[]? | select(.name == \"$2\") | .id" 2>/dev/null | head -1
}

build_payload() {
    local name="$1" branch="$2" checks_json="$3"
    jq -n --arg name "$name" \
          --arg ref "refs/heads/$branch" \
          --argjson checks "$checks_json" '
    {
      name: $name,
      target: "branch",
      enforcement: "active",
      bypass_actors: [],
      conditions: { ref_name: { include: [$ref], exclude: [] } },
      rules: (
        [
          { type: "deletion" },
          { type: "non_fast_forward" },
          { type: "pull_request",
            parameters: {
              required_approving_review_count: 0,
              require_code_owner_review: false,
              require_last_push_approval: false,
              dismiss_stale_reviews_on_push: true,
              required_review_thread_resolution: true,
              allowed_merge_methods: ["merge", "squash", "rebase"]
            } }
        ]
        + (if ($checks | length) > 0 then
             [ { type: "required_status_checks",
                 parameters: {
                   strict_required_status_checks_policy: false,
                   do_not_enforce_on_create: true,
                   required_status_checks: [ $checks[] | { context: . } ]
                 } } ]
           else [] end)
      )
    }'
}

build_tag_payload() {
    jq -n '{
      name: "protected-tags",
      target: "tag",
      enforcement: "active",
      bypass_actors: [],
      conditions: { ref_name: { include: ["~ALL"], exclude: [] } },
      rules: [ { type: "deletion" }, { type: "update" } ]
    }'
}

exit_code=0
withheld_total=0

for repo in $(jq -r '.repos | keys[]' "$POLICY"); do
    echo "── $repo"
    for branch in $(jq -r --arg r "$repo" '.repos[$r].branches | keys[]' "$POLICY"); do
        name="protected-$branch"
        # Per branch, not per repository: a trigger covers specific branches,
        # and a repo-wide "verified" would vouch for a branch it never listed.
        verified="$(jq -r --arg r "$repo" --arg b "$branch" \
            '.repos[$r].branches[$b].verified // ""' "$POLICY")"

        if ! gh api "repos/$OWNER/$repo/branches/$branch" --jq '.name' >/dev/null 2>&1; then
            echo "   ! $branch — branch does not exist, skipping"
            exit_code=1
            continue
        fi

        mapfile -t wanted < <(jq -r --arg r "$repo" --arg b "$branch" \
            '.repos[$r].branches[$b].checks[]?' "$POLICY")

        seen="$(observed_checks "$repo" "$branch")"
        safe=()
        for check in "${wanted[@]:-}"; do
            [[ -z "$check" ]] && continue
            # Necessary in both tiers: a context the base branch does not
            # declare cannot report on a pull request into it, however many
            # times it has reported elsewhere.
            if ! declared_in_repo "$repo" "$check"; then
                echo "   ! $branch — withholding '$check': no workflow in this repository declares it"
                withheld_total=$((withheld_total + 1))
            elif grep -qxF "$check" <<< "$seen"; then
                safe+=("$check")                       # tier 1
            elif [[ -n "$verified" ]]; then
                safe+=("$check")                       # tier 2
                echo "   · $branch — '$check' required on a verified trigger, not on observed runs"
            else
                echo "   ! $branch — withholding '$check': no evidence it reports here"
                withheld_total=$((withheld_total + 1))
            fi
        done

        if [[ ${#safe[@]} -gt 0 ]]; then
            checks_json="$(printf '%s\n' "${safe[@]}" | jq -R . | jq -sc .)"
        else
            checks_json="[]"
        fi

        id="$(ruleset_id_named "$repo" "$name")"

        case "$MODE" in
        verify)
            # A required context that is not reporting on an OPEN pull request
            # is the deadlock this script exists to prevent, seen from the other
            # end. It cannot always be predicted when the ruleset is written —
            # a branch cut before the job existed carries no workflow that
            # produces it — so it is detected here instead, where the fix is
            # obvious: update the branch from base, or merge the PR that adds
            # the job.
            while IFS=$'\t' read -r pr_num pr_sha; do
                [[ -z "$pr_num" ]] && continue
                # </dev/null matters: without it `gh` inherits the loop's
                # stdin and eats the next line of the pull-request list, so the
                # loop reads a number that never came out of `gh pr list`.
                reported="$(gh api "repos/$OWNER/$repo/commits/$pr_sha/check-runs?per_page=100" \
                            --jq '.check_runs[].name' </dev/null 2>/dev/null | sort -u)"
                for check in "${safe[@]:-}"; do
                    [[ -z "$check" ]] && continue
                    grep -qxF "$check" <<< "$reported" && continue
                    echo "   ✗ $branch — PR #$pr_num is stuck: '$check' is required and has not reported"
                    exit_code=1
                done
            done < <(gh pr list --repo "$OWNER/$repo" --base "$branch" --state open \
                       --json number,headRefOid --jq '.[] | [.number, .headRefOid] | @tsv' 2>/dev/null)

            if [[ -z "$id" ]]; then
                echo "   ✗ $branch — no '$name' ruleset"
                exit_code=1
            else
                gh api "repos/$OWNER/$repo/rulesets/$id" --jq \
                  '"   ✓ '"$branch"' id=\(.id) \(.enforcement) bypass=\(.bypass_actors|length) rules=\([.rules[].type]|join(","))"'
                if [[ "$(gh api "repos/$OWNER/$repo/rulesets/$id" --jq '.bypass_actors|length')" != "0" ]]; then
                    echo "   ✗ $branch — a bypass actor is configured"
                    exit_code=1
                fi
            fi
            ;;
        dry-run)
            echo "   → $branch: checks=[${safe[*]:-}] — would $([[ -n "$id" ]] && echo "update $id" || echo "create")"
            ;;
        apply)
            payload="$(build_payload "$name" "$branch" "$checks_json")"
            if [[ -n "$id" ]]; then
                printf '%s' "$payload" | gh api -X PUT "repos/$OWNER/$repo/rulesets/$id" \
                    --input - --jq '"   ✓ '"$branch"' updated ruleset \(.id)"' || {
                    echo "   ✗ $branch — update failed"; exit_code=1; }
            else
                printf '%s' "$payload" | gh api -X POST "repos/$OWNER/$repo/rulesets" \
                    --input - --jq '"   ✓ '"$branch"' created ruleset \(.id)"' || {
                    echo "   ✗ $branch — create failed"; exit_code=1; }
            fi
            ;;
        esac
    done

    # Tags, opt-in per repository. A tag ruleset has no status checks and no
    # pull requests — the only thing worth saying about a release tag is that
    # it may not be moved or deleted, so that the version somebody installed
    # keeps pointing at the code it claimed to.
    if [[ "$(jq -r --arg r "$repo" '.repos[$r].protect_tags // false' "$POLICY")" == "true" ]]; then
        tag_id="$(ruleset_id_named "$repo" "protected-tags")"
        case "$MODE" in
        verify)
            if [[ -z "$tag_id" ]]; then
                echo "   ✗ tags — no 'protected-tags' ruleset"
                exit_code=1
            else
                gh api "repos/$OWNER/$repo/rulesets/$tag_id" --jq \
                  '"   ✓ tags id=\(.id) \(.enforcement) bypass=\(.bypass_actors|length) rules=\([.rules[].type]|join(\",\"))"'
            fi
            ;;
        dry-run)
            echo "   → tags: would $([[ -n "$tag_id" ]] && echo "update $tag_id" || echo "create")"
            ;;
        apply)
            if [[ -n "$tag_id" ]]; then
                build_tag_payload | gh api -X PUT "repos/$OWNER/$repo/rulesets/$tag_id" \
                    --input - --jq '"   ✓ tags updated ruleset \(.id)"' || {
                    echo "   ✗ tags — update failed"; exit_code=1; }
            else
                build_tag_payload | gh api -X POST "repos/$OWNER/$repo/rulesets" \
                    --input - --jq '"   ✓ tags created ruleset \(.id)"' || {
                    echo "   ✗ tags — create failed"; exit_code=1; }
            fi
            ;;
        esac
    fi
done

echo
[[ $withheld_total -gt 0 ]] && echo "$withheld_total check(s) withheld — fix the trigger or record a verification, then re-run."
exit $exit_code
