#!/usr/bin/env bash
#
# Rule: changelog
# Ensure CHANGELOG is updated with code changes
#

rule_changelog() {
    local scope="$1"
    set_current_rule "changelog"
    
    # Only enforce on push/pr scopes
    case "$scope" in
        push|pr|range:*)
            ;;
        *)
            rule_skip "only runs on push/pr scope"
            return 3
            ;;
    esac
    
    local files
    files="$(get_scope_files "$scope")"
    
    if [[ -z "$files" ]]; then
        rule_skip "no files changed"
        return 3
    fi
    
    # Get trigger pattern (which files require changelog update)
    local trigger_pattern
    trigger_pattern="$(config_get_trigger changelog '\.(js|ts|jsx|tsx|py|go|rs|java|rb|php|c|cpp|h)$')"
    
    # Check if any source files changed
    local src_changed=0
    while IFS= read -r file; do
        if [[ "$file" =~ $trigger_pattern ]]; then
            src_changed=1
            break
        fi
    done <<< "$files"
    
    if [[ $src_changed -eq 0 ]]; then
        rule_skip "no source files changed"
        return 3
    fi
    
    # Check if CHANGELOG was updated
    if echo "$files" | grep -qiE '(CHANGELOG|CHANGES|HISTORY)\.(md|txt|rst)$'; then
        rule_pass "changelog updated"
        return 0
    fi
    
    rule_warn "source files changed but CHANGELOG not updated"
    return 2
}
