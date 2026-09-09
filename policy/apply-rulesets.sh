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
            if grep -qxF "$check" <<< "$seen"; then
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
done

echo
[[ $withheld_total -gt 0 ]] && echo "$withheld_total check(s) withheld — fix the trigger or record a verification, then re-run."
exit $exit_code
