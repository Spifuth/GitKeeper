#!/usr/bin/env bash
#
# Rule: branch_name
# Enforce branch naming conventions
#

rule_branch_name() {
    local scope="$1"
    set_current_rule "branch_name"
    
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    
    if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        rule_skip "detached HEAD"
        return 3
    fi
    
    # Skip main branches
    if [[ "$branch" =~ ^(main|master|develop|dev)$ ]]; then
        rule_pass "$branch"
        return 0
    fi
    
    # Get naming pattern from config
    local pattern
    pattern="$(config_get_pattern branch_name '^(feature|bugfix|hotfix|release|chore)/[a-z0-9][a-z0-9-]*$')"
    
    if [[ "$branch" =~ $pattern ]]; then
        rule_pass "$branch"
        return 0
    fi
    
    rule_warn "'$branch' doesn't match pattern"
    echo -e "      ${DIM}Expected: $pattern${NC}"
    return 2
}
