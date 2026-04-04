#!/usr/bin/env bash
#
# GitKeeper - check command
# Run rules against a scope, with per-directory config support.
#
# When subdirectory .gitkeeper.conf files exist, changed files are grouped
# by their nearest config. Each group is checked independently with its
# merged config (root + subdirectory overlay). Rules see only the files
# that belong to their group via the GITKEEPER_FILE_FILTER env var.
#

cmd_check() {
    local scope="staged"
    local quiet=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)       scope="$2";            shift 2 ;;
            --scope=*)     scope="${1#--scope=}";  shift   ;;
            -v|--verbose)  export GITKEEPER_VERBOSE=1; shift ;;
            -q|--quiet)    quiet=1; export GITKEEPER_QUIET=1; shift ;;
            *)             die "unknown option: $1" ;;
        esac
    done

    if ! validate_scope "$scope"; then
        die "invalid scope: $scope"
    fi

    # ── Find and load root config ──────────────────────────────────────────
    local root_config=""
    if root_config="$(find_config)"; then
        parse_config "$root_config"
    else
        parse_config ""
    fi

    # ── Header ────────────────────────────────────────────────────────────
    print_header "GitKeeper Check"
    echo ""
    log_info "Scope: $(describe_scope "$scope")"

    local total_files
    total_files="$(count_scope_files "$scope")"
    log_info "Files: $total_files"

    [[ -n "$root_config" ]] && log_debug "Config: $root_config"
    echo ""

    # ── Gather all files and look for subdirectory configs ─────────────────
    local all_files
    all_files="$(get_scope_files "$scope")"

    local repo_root
    repo_root="$(get_repo_root)"

    # Detect whether any changed file lives under a subdirectory config.
    # We do one fast pass rather than grouping everything if there are none.
    local has_dir_configs=0
    if [[ -n "$all_files" ]]; then
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            if find_dir_config_for_file "$file" "$repo_root" "$root_config" &>/dev/null; then
                has_dir_configs=1
                break
            fi
        done <<< "$all_files"
    fi

    # ── Grand totals (accumulated across all groups) ───────────────────────
    local grand_passed=0
    local grand_warned=0
    local grand_failed=0
    local grand_skipped=0

    # ── Single-config path (fast path, no grouping overhead) ──────────────
    if [[ $has_dir_configs -eq 0 ]]; then
        print_header "Rules"
        run_all_rules "$scope"

        grand_passed="${GITKEEPER_SUMMARY_PASSED:-0}"
        grand_warned="${GITKEEPER_SUMMARY_WARNED:-0}"
        grand_failed="${GITKEEPER_SUMMARY_FAILED:-0}"
        grand_skipped="${GITKEEPER_SUMMARY_SKIPPED:-0}"

    # ── Multi-config path ──────────────────────────────────────────────────
    else
        log_info "Per-directory configs detected — running grouped checks"
        echo ""

        # Build groups: associative array of config_path → newline-delimited files
        declare -A config_groups=()
        declare -a config_order=()   # preserve encounter order for output

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue

            local config_key
            local dir_config
            if dir_config="$(find_dir_config_for_file "$file" "$repo_root" "$root_config" 2>/dev/null)"; then
                config_key="$dir_config"
            else
                config_key="${root_config:-__none__}"
            fi

            if [[ -z "${config_groups[$config_key]+set}" ]]; then
                config_order+=("$config_key")
                config_groups["$config_key"]="$file"
            else
                config_groups["$config_key"]+=$'\n'"$file"
            fi
        done <<< "$all_files"

        # Run rules for each group
        for config_key in "${config_order[@]}"; do
            local group_files="${config_groups[$config_key]}"
            local group_file_count
            group_file_count="$(echo "$group_files" | grep -c . || true)"

            # ── Section header ─────────────────────────────────────────────
            local section_label
            if [[ "$config_key" == "$root_config" || "$config_key" == "__none__" ]]; then
                section_label="root"
            else
                section_label="$(dirname "$config_key" | sed "s|^${repo_root}/||")"
            fi

            echo ""
            print_header "Rules — ${section_label}/ (${group_file_count} file(s))"

            if [[ "$config_key" != "$root_config" && "$config_key" != "__none__" ]]; then
                log_debug "Overlay: $config_key"
            fi

            # ── Load config for this group ─────────────────────────────────
            # Always start fresh from root, then layer the dir overlay on top.
            if [[ -n "$root_config" ]]; then
                parse_config "$root_config"
            else
                parse_config ""
            fi

            if [[ "$config_key" != "$root_config" && "$config_key" != "__none__" ]]; then
                apply_config_overlay "$config_key"
            fi

            # ── Set file filter so scope functions restrict to this group ───
            export GITKEEPER_FILE_FILTER="$group_files"

            # ── Run rules ──────────────────────────────────────────────────
            run_all_rules "$scope"

            # Accumulate
            (( grand_passed  += ${GITKEEPER_SUMMARY_PASSED:-0}  )) || true
            (( grand_warned  += ${GITKEEPER_SUMMARY_WARNED:-0}  )) || true
            (( grand_failed  += ${GITKEEPER_SUMMARY_FAILED:-0}  )) || true
            (( grand_skipped += ${GITKEEPER_SUMMARY_SKIPPED:-0} )) || true
        done

        # Clean up filter so any code after this sees the full scope again
        unset GITKEEPER_FILE_FILTER
    fi

    # ── Summary ────────────────────────────────────────────────────────────
    echo ""
    print_separator

    local status_parts=()
    [[ $grand_passed  -gt 0 ]] && status_parts+=("${GREEN}${grand_passed} passed${NC}")
    [[ $grand_warned  -gt 0 ]] && status_parts+=("${YELLOW}${grand_warned} warnings${NC}")
    [[ $grand_failed  -gt 0 ]] && status_parts+=("${RED}${grand_failed} failed${NC}")
    [[ $grand_skipped -gt 0 ]] && status_parts+=("${DIM}${grand_skipped} skipped${NC}")

    local status_line
    status_line="$(IFS=', '; echo "${status_parts[*]}")"
    echo -e "$status_line"
    echo ""

    if [[ $grand_failed -gt 0 ]]; then
        log_error "Check failed"
        exit "$EXIT_ERROR"
    elif [[ $grand_warned -gt 0 ]] && config_fail_on_warn; then
        log_warn "Check failed (fail_on=warn)"
        exit "$EXIT_WARN"
    elif [[ $grand_warned -gt 0 ]]; then
        log_warn "Check passed with warnings"
        exit "$EXIT_OK"
    else
        log_success "All checks passed"
        exit "$EXIT_OK"
    fi
}
