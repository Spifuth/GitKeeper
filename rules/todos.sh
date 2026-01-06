#!/usr/bin/env bash
#
# Rule: todos
# Track new TODO/FIXME comments
#

rule_todos() {
    local scope="$1"
    set_current_rule "todos"
    
    local diff
    diff="$(get_scope_diff "$scope")"
    
    if [[ -z "$diff" ]]; then
        rule_skip "no changes to check"
        return 3
    fi
    
    # Look for new TODOs in added lines
    local todo_pattern='\b(TODO|FIXME|XXX|HACK|BUG)\b'
    local new_todos
    new_todos="$(echo "$diff" | grep -E '^\+' | grep -v '^+++' | grep -Ei "$todo_pattern" || true)"
    
    if [[ -z "$new_todos" ]]; then
        rule_pass
        return 0
    fi
    
    local count
    count="$(echo "$new_todos" | wc -l | xargs)"
    
    rule_warn "$count new TODO/FIXME comment(s)"
    echo "$new_todos" | head -3 | while IFS= read -r line; do
        echo -e "      ${DIM}${line:0:70}${NC}"
    done
    
    return 2
}
