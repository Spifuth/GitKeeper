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
# Scope resolution
#------------------------------------------------------------------------------

get_scope_range() {
    local scope="$1"
    case "$scope" in
        staged)  echo "--cached" ;;
        push)
            local upstream
            upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo 'origin/main')"
            echo "${upstream}..HEAD"
            ;;
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
            local upstream
            upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo 'origin/main')"
            raw_files="$(git diff --name-only "${upstream}..HEAD" 2>/dev/null)"
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
            local upstream
            upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo 'origin/main')"
            _git_diff_with_pathspec git diff "${upstream}..HEAD"
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
