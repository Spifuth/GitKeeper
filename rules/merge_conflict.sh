#!/usr/bin/env bash
#
# Rule: merge_conflict
# Detect leftover merge conflict markers
#

rule_merge_conflict() {
    local scope="$1"
    set_current_rule "merge_conflict"
    
    local diff
    diff="$(get_scope_diff "$scope")"
    
    if [[ -z "$diff" ]]; then
        rule_skip "no changes to check"
        return 3
    fi
    
    # Check for conflict markers in added lines
    # Pattern matches: +<<<<<<<, +=======, +>>>>>>> at line start (with optional leading whitespace)
    # Excludes markers in strings, comments, or documentation (with backticks)
    local conflict_pattern='^\+[[:space:]]*(<<<<<<< |=======$|>>>>>>> )'
    
    # Also check for the bare markers
    local bare_pattern='^\+(<<<<<<<|=======|>>>>>>>)$'
    
    local found=0
    if echo "$diff" | grep -qE "$conflict_pattern"; then
        found=1
    elif echo "$diff" | grep -qE "$bare_pattern"; then
        found=1
    fi
    
    if [[ $found -eq 1 ]]; then
        rule_fail "merge conflict markers found"
        echo "$diff" | grep -E "$conflict_pattern|$bare_pattern" | head -3 | while IFS= read -r line; do
            echo -e "      ${RED}${line:0:60}${NC}"
        done
        return 1
    fi
    
    rule_pass
    return 0
}
