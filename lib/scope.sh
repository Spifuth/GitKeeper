#!/usr/bin/env bash
#
# GitKeeper - Scope resolution
# Determine what files/commits to check based on scope
#

#------------------------------------------------------------------------------
# Scope types
#------------------------------------------------------------------------------

# Validate a scope string
validate_scope() {
    local scope="$1"
    
    case "$scope" in
        staged|push|pr|stash|all)
            return 0
            ;;
        range:*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get human-readable scope description
describe_scope() {
    local scope="$1"
    
    case "$scope" in
        staged)
            echo "files staged for commit"
            ;;
        push)
            echo "commits to be pushed"
            ;;
        pr)
            echo "pull request diff"
            ;;
        stash)
            echo "stash contents"
            ;;
        all)
            echo "all tracked files"
            ;;
        range:*)
            echo "range ${scope#range:}"
            ;;
        *)
            echo "unknown scope"
            ;;
    esac
}

#------------------------------------------------------------------------------
# Scope resolution
#------------------------------------------------------------------------------

# Get the git range for a scope
get_scope_range() {
    local scope="$1"
    
    case "$scope" in
        staged)
            echo "--cached"
            ;;
        push)
            local upstream
            upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo 'origin/main')"
            echo "${upstream}..HEAD"
            ;;
        pr)
            local base="${GITKEEPER_PR_BASE:-origin/main}"
            echo "${base}...HEAD"
            ;;
        stash)
            echo "stash@{0}"
            ;;
        range:*)
            echo "${scope#range:}"
            ;;
        all)
            echo "HEAD"
            ;;
    esac
}

# Get list of files in scope
get_scope_files() {
    local scope="$1"
    
    case "$scope" in
        staged)
            git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
            ;;
        push)
            local upstream
            upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo 'origin/main')"
            git diff --name-only "${upstream}..HEAD" 2>/dev/null
            ;;
        pr)
            local base="${GITKEEPER_PR_BASE:-origin/main}"
            git diff --name-only "${base}...HEAD" 2>/dev/null
            ;;
        stash)
            git stash show --name-only 2>/dev/null || true
            ;;
        range:*)
            local range="${scope#range:}"
            git diff --name-only "$range" 2>/dev/null
            ;;
        all)
            git ls-files 2>/dev/null
            ;;
        *)
            die "unknown scope: $scope"
            ;;
    esac
}

# Get diff content for scope
get_scope_diff() {
    local scope="$1"
    
    case "$scope" in
        staged)
            git diff --cached 2>/dev/null
            ;;
        push)
            local upstream
            upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo 'origin/main')"
            git diff "${upstream}..HEAD" 2>/dev/null
            ;;
        pr)
            local base="${GITKEEPER_PR_BASE:-origin/main}"
            git diff "${base}...HEAD" 2>/dev/null
            ;;
        stash)
            git stash show -p 2>/dev/null || true
            ;;
        range:*)
            local range="${scope#range:}"
            git diff "$range" 2>/dev/null
            ;;
        all)
            # Return empty: get_scope_files for 'all' uses git ls-files (every
            # tracked file), so returning only uncommitted changes here would
            # give mismatched data. Content-based rules must use get_scope_files
            # for this scope instead of get_scope_diff.
            echo ""
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

# Count files in scope
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

# Check if scope has any changes
scope_has_changes() {
    local scope="$1"
    local files
    files="$(get_scope_files "$scope")"
    
    [[ -n "$files" ]]
}
