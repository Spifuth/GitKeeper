#!/usr/bin/env bash
#
# GitKeeper - check command
# Run rules against a scope
#

cmd_check() {
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
            -v|--verbose)
                export GITKEEPER_VERBOSE=1
                shift
                ;;
            -q|--quiet)
                export GITKEEPER_QUIET=1
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
    
    # Header
    print_header "GitKeeper Check"
    echo ""
    log_info "Scope: $(describe_scope "$scope")"
    
    local file_count
    file_count="$(count_scope_files "$scope")"
    log_info "Files: $file_count"
    
    if [[ -n "$config" ]]; then
        log_debug "Config: $config"
    fi
    echo ""
    
    # Run rules
    print_header "Rules"
    run_all_rules "$scope"
    
    # Get summary from global variables
    local total="${GITKEEPER_SUMMARY_TOTAL:-0}"
    local passed="${GITKEEPER_SUMMARY_PASSED:-0}"
    local warned="${GITKEEPER_SUMMARY_WARNED:-0}"
    local failed="${GITKEEPER_SUMMARY_FAILED:-0}"
    local skipped="${GITKEEPER_SUMMARY_SKIPPED:-0}"
    
    echo ""
    print_separator
    
    # Summary line
    local status_parts=()
    [[ $passed -gt 0 ]] && status_parts+=("${GREEN}${passed} passed${NC}")
    [[ $warned -gt 0 ]] && status_parts+=("${YELLOW}${warned} warnings${NC}")
    [[ $failed -gt 0 ]] && status_parts+=("${RED}${failed} failed${NC}")
    [[ $skipped -gt 0 ]] && status_parts+=("${DIM}${skipped} skipped${NC}")
    
    local status_line
    status_line="$(IFS=', '; echo "${status_parts[*]}")"
    echo -e "$status_line"
    echo ""
    
    # Determine exit code
    if [[ $failed -gt 0 ]]; then
        log_error "Check failed"
        exit "$EXIT_ERROR"
    elif [[ $warned -gt 0 ]] && config_fail_on_warn; then
        log_warn "Check failed (fail_on=warn)"
        exit "$EXIT_WARN"
    elif [[ $warned -gt 0 ]]; then
        log_warn "Check passed with warnings"
        exit "$EXIT_OK"
    else
        log_success "All checks passed"
        exit "$EXIT_OK"
    fi
}
