#!/usr/bin/env bash
#
# GitKeeper - explain command
# Debug/preview what will be checked
#

cmd_explain() {
    local scope="staged"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                scope="$2"
                shift 2
                ;;
            --scope=*)
                scope="${1#--scope=}"
                shift
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
    
    # Validate scope
    if ! validate_scope "$scope"; then
        die "invalid scope: $scope"
    fi
    
    # Find and parse config
    local config=""
    if config="$(find_config)"; then
        parse_config "$config"
    else
        parse_config ""
    fi
    
    print_header "GitKeeper Explain"
    echo ""
    
    # Config
    print_header "Configuration"
    if [[ -n "$config" ]]; then
        echo "  File: $config"
    else
        echo "  File: (none, using defaults)"
    fi
    echo "  Fail on: $GITKEEPER_FAIL_ON"
    echo ""
    
    # Scope
    print_header "Scope"
    echo "  Type: $scope"
    echo "  Description: $(describe_scope "$scope")"
    echo "  Git range: $(get_scope_range "$scope")"
    echo ""
    
    # Files in scope
    print_header "Files in Scope"
    local files
    files="$(get_scope_files "$scope")"
    local file_count
    file_count="$(count_scope_files "$scope")"
    
    echo "  Count: $file_count"
    if [[ -n "$files" ]]; then
        echo ""
        echo "$files" | head -20 | while read -r f; do
            echo "    $f"
        done
        if [[ $file_count -gt 20 ]]; then
            echo "    ... and $((file_count - 20)) more"
        fi
    fi
    echo ""
    
    # Rules to run
    print_header "Rules to Run"
    local rules_string
    rules_string="$(config_get_rules)"
    IFS=',' read -ra rules <<< "$rules_string"
    
    for rule in "${rules[@]}"; do
        rule="$(trim "$rule")"
        [[ -z "$rule" ]] && continue
        
        if rule_exists "$rule"; then
            echo -e "  ${GREEN}✓${NC} $rule"
        else
            echo -e "  ${YELLOW}?${NC} $rule (not found)"
        fi
    done
    echo ""
    
    # Available rules
    print_header "Available Rules"
    local available_rules
    available_rules="$(list_available_rules | sort)" || true
    for rule in $available_rules; do
        if echo ",$rules_string," | grep -q ",$rule," 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $rule (enabled)"
        else
            echo -e "  ${DIM}○${NC} $rule"
        fi
    done
}
