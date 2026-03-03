#!/usr/bin/env bash
#
# Rule: version
# Check for version file updates
#

rule_version() {
    local scope="$1"
    set_current_rule "version"
    
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
    
    # Get version files to check
    local version_files
    version_files="$(config_get_required version 'package.json,version.txt,VERSION,setup.py,Cargo.toml,pyproject.toml')"
    
    IFS=',' read -ra vfiles <<< "$version_files"
    for vfile in "${vfiles[@]}"; do
        vfile="$(trim "$vfile")"
        if echo "$files" | grep -qE "(^|/)${vfile}$"; then
            rule_pass "$vfile updated"
            return 0
        fi
    done
    
    # No version file updated - this is just informational
    rule_skip "no version file in changes"
    return 3
}
