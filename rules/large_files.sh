#!/usr/bin/env bash
#
# Rule: large_files
# Prevent large files from being committed
#

rule_large_files() {
    local scope="$1"
    set_current_rule "large_files"
    
    local files
    files="$(get_scope_files "$scope")"
    
    if [[ -z "$files" ]]; then
        rule_skip "no files to check"
        return 3
    fi
    
    # Get max size from config (default: 5MB)
    local max_size
    max_size="$(config_get_pattern large_files '5242880')"
    
    local found=0
    local large_files=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue
        
        local size
        # Linux stat
        size="$(stat -c%s "$file" 2>/dev/null)" || \
        # macOS stat
        size="$(stat -f%z "$file" 2>/dev/null)" || \
        size=0
        
        if [[ $size -gt $max_size ]]; then
            found=1
            local size_mb=$((size / 1024 / 1024))
            large_files+=("$file (${size_mb}MB)")
        fi
    done <<< "$files"
    
    if [[ $found -eq 1 ]]; then
        local max_mb=$((max_size / 1024 / 1024))
        rule_fail "${#large_files[@]} file(s) exceed ${max_mb}MB"
        for f in "${large_files[@]:0:5}"; do
            echo -e "      ${RED}$f${NC}"
        done
        return 1
    fi
    
    rule_pass
    return 0
}
