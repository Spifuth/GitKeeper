#!/usr/bin/env bash
#
# Rule: readme
# Verify README exists in repository
#

rule_readme() {
    local scope="$1"
    set_current_rule "readme"
    
    # Check for README in repo root
    local readme_found=0
    for readme in README.md README.rst README.txt README; do
        if [[ -f "$readme" ]]; then
            readme_found=1
            break
        fi
    done
    
    if [[ $readme_found -eq 1 ]]; then
        rule_pass
        return 0
    fi
    
    rule_warn "no README file found"
    return 2
}
