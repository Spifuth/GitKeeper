#!/usr/bin/env bash
#
# GitKeeper - Scope resolution
# Determine what files/commits to check based on scope
#
# Per-directory config support:
#   If GITKEEPER_FILE_FILTER is set (newline-separated list of paths),
#   get_scope_files and get_scope_diff silently restrict their output to
#   only those files. This allows cmd_check to run rules once per config
#   group without any rule needing to know about the grouping.
#

#------------------------------------------------------------------------------
# Scope types
#------------------------------------------------------------------------------

validate_scope() {
    local scope="$1"
    case "$scope" in
        staged|push|pr|stash|all) return 0 ;;
        range:*)                  return 0 ;;
        *)                        return 1 ;;
    esac
}

describe_scope() {
    local scope="$1"
    case "$scope" in
        staged)  echo "files staged for commit" ;;
        push)    echo "commits to be pushed" ;;
        pr)      echo "pull request diff" ;;
        stash)   echo "stash contents" ;;
        all)     echo "all tracked files" ;;
        range:*) echo "range ${scope#range:}" ;;
        *)       echo "unknown scope" ;;
    esac
}

#------------------------------------------------------------------------------
# Internal helper: apply GITKEEPER_FILE_FILTER to a file list
# Takes a newline-separated list on stdin, emits filtered list on stdout.
# If GITKEEPER_FILE_FILTER is empty, passes through unchanged.
#------------------------------------------------------------------------------
_apply_file_filter() {
    local all_files
    all_files="$(cat)"

    if [[ -z "${GITKEEPER_FILE_FILTER:-}" ]]; then
        echo "$all_files"
        return
    fi

    # grep -xFf: match exact full lines (-x) from a fixed-string (-F) patterns
    # file (-f). Each line in GITKEEPER_FILE_FILTER is a pattern.
    echo "$all_files" \
        | grep -xFf <(echo "$GITKEEPER_FILE_FILTER") 2>/dev/null \
        || true
}

#------------------------------------------------------------------------------
# Push ranges
#
# The push scope is the commits being pushed, not "everything since main".
# It used to fall back to a hardcoded `origin/main` whenever a branch had no
# upstream, so the first push of every new branch re-scanned everything `dev`
# carries ahead of `main` — and one false positive on `dev` blocked every
# branch in the repo, whatever it contained.
#------------------------------------------------------------------------------

# Base of the commits reachable from $1 that no remote-tracking ref has.
# Prints nothing and returns 1 when the remote already has all of them.
_unpushed_base() {
    local tip="$1"
    local first
    first="$(git rev-list --reverse --topo-order "$tip" --not --remotes 2>/dev/null | head -n 1)"
    [[ -z "$first" ]] && return 1

    if git rev-parse -q --verify "${first}^" >/dev/null 2>&1; then
        git rev-parse "${first}^"
    else
        # A root commit: diff against the empty tree.
        git hash-object -t tree /dev/null
    fi
}

# Reads git's pre-push stdin — "<local ref> <local sha> <remote ref> <remote sha>"
# per line — and prints one "base..tip" range per ref that actually sends commits.
# Deletions, and new refs whose commits the remote already has, print nothing.
resolve_push_ranges() {
    local local_sha remote_sha base
    # -t: never hang on a stdin that is a pipe nobody closes.
    while read -r -t 10 _ local_sha _ remote_sha; do
        [[ "$local_sha" =~ ^[0-9a-f]{40,64}$ ]] || continue
        [[ "$local_sha" =~ ^0+$ ]] && continue

        if [[ ! "$remote_sha" =~ ^0+$ ]] \
            && git cat-file -e "${remote_sha}^{commit}" 2>/dev/null; then
            echo "${remote_sha}..${local_sha}"
        elif base="$(_unpushed_base "$local_sha")"; then
            echo "${base}..${local_sha}"
        fi
    done
    return 0
}

# The ranges the push scope covers, one per line. GITKEEPER_PUSH_RANGES (set
# from the pre-push hook's stdin by cmd_check) wins; otherwise the upstream;
# otherwise only what no remote has yet.
_push_ranges() {
    if [[ -n "${GITKEEPER_PUSH_RANGES+set}" ]]; then
        [[ -n "$GITKEEPER_PUSH_RANGES" ]] && echo "$GITKEEPER_PUSH_RANGES"
        return 0
    fi

    local upstream base
    if upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"; then
        echo "${upstream}..HEAD"
    elif base="$(_unpushed_base HEAD)"; then
        echo "${base}..HEAD"
    fi
}

#------------------------------------------------------------------------------
# Scope resolution
#------------------------------------------------------------------------------

get_scope_range() {
    local scope="$1"
    case "$scope" in
        staged)  echo "--cached" ;;
        push)    _push_ranges | paste -sd ' ' - ;;
        pr)
            local base="${GITKEEPER_PR_BASE:-origin/main}"
            echo "${base}...HEAD"
            ;;
        stash)   echo "stash@{0}" ;;
        range:*) echo "${scope#range:}" ;;
        all)     echo "HEAD" ;;
    esac
}

# Get list of files in scope, filtered by GITKEEPER_FILE_FILTER when set.
get_scope_files() {
    local scope="$1"

    local raw_files
    case "$scope" in
        staged)
            raw_files="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)"
            ;;
        push)
            # ACMR, like staged: a file the push deletes is not a file it adds.
            local range
            raw_files="$(
                while IFS= read -r range; do
                    [[ -n "$range" ]] && git diff --name-only --diff-filter=ACMR "$range" 2>/dev/null
                done < <(_push_ranges) | sort -u
            )"
            ;;
        pr)
            local base="${GITKEEPER_PR_BASE:-origin/main}"
            raw_files="$(git diff --name-only "${base}...HEAD" 2>/dev/null)"
            ;;
        stash)
            raw_files="$(git stash show --name-only 2>/dev/null || true)"
            ;;
        range:*)
            local range="${scope#range:}"
            raw_files="$(git diff --name-only "$range" 2>/dev/null)"
            ;;
        all)
            raw_files="$(git ls-files 2>/dev/null)"
            ;;
        *)
            die "unknown scope: $scope"
            ;;
    esac

    echo "$raw_files" | _apply_file_filter
}

# Get diff content for scope.
# When GITKEEPER_FILE_FILTER is set, restricts the diff to only those files
# using git's -- pathspec argument.
get_scope_diff() {
    local scope="$1"

    # Build the -- pathspec if a filter is active
    local pathspec=()
    if [[ -n "${GITKEEPER_FILE_FILTER:-}" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] && pathspec+=("$f")
        done <<< "$GITKEEPER_FILE_FILTER"
    fi

    # Helper to optionally append -- <files> to a git diff command
    _git_diff_with_pathspec() {
        if [[ ${#pathspec[@]} -gt 0 ]]; then
            "$@" -- "${pathspec[@]}" 2>/dev/null
        else
            "$@" 2>/dev/null
        fi
    }

    case "$scope" in
        staged)
            _git_diff_with_pathspec git diff --cached
            ;;
        push)
            local range
            while IFS= read -r range; do
                [[ -n "$range" ]] && _git_diff_with_pathspec git diff "$range"
            done < <(_push_ranges)
            ;;
        pr)
            local base="${GITKEEPER_PR_BASE:-origin/main}"
            _git_diff_with_pathspec git diff "${base}...HEAD"
            ;;
        stash)
            # git stash show -p doesn't accept -- pathspec cleanly in all versions;
            # fall back to full stash diff and filter manually
            local stash_diff
            stash_diff="$(git stash show -p 2>/dev/null || true)"
            if [[ ${#pathspec[@]} -gt 0 && -n "$stash_diff" ]]; then
                git diff stash@{0} HEAD -- "${pathspec[@]}" 2>/dev/null || true
            else
                echo "$stash_diff"
            fi
            ;;
        range:*)
            local range="${scope#range:}"
            _git_diff_with_pathspec git diff "$range"
            ;;
        all)
            # For 'all' scope, diff is uncommitted changes only.
            # File-based rules should use get_scope_files instead.
            if [[ ${#pathspec[@]} -gt 0 ]]; then
                git diff HEAD -- "${pathspec[@]}" 2>/dev/null
            else
                git diff HEAD 2>/dev/null
            fi
            ;;
        *)
            die "unknown scope: $scope"
            ;;
    esac
}

# Get added lines only from diff (lines starting with +, excluding +++)
get_scope_additions() {
    local scope="$1"
    get_scope_diff "$scope" | grep '^+' | grep -v '^+++' || true
}

# Count files in scope (respects filter)
count_scope_files() {
    local scope="$1"
    local files
    files="$(get_scope_files "$scope")"

    if [[ -z "$files" ]]; then
        echo 0
    else
        echo "$files" | wc -l | xargs
    fi
}

# Check if scope has any changes (respects filter)
scope_has_changes() {
    local scope="$1"
    local files
    files="$(get_scope_files "$scope")"
    [[ -n "$files" ]]
}
