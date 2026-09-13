#!/usr/bin/env bash
#
# Rule: no_debug
# Block debug statements from being committed
#
# Detects language-specific debug calls in added lines only.
# Fails by default; set no_debug_warn=1 in config to demote to a warning.
#
# Config keys:
#   pattern_no_debug    — comma-separated extra patterns to check
#   no_debug_warn       — set to 1 to warn instead of fail
#   no_debug_exclude    — comma-separated file name suffixes to skip
#                         (default covers common test file patterns)
#

rule_no_debug() {
    local scope="$1"
    set_current_rule "no_debug"

    local diff
    diff="$(get_scope_diff "$scope")"

    if [[ -z "$diff" ]]; then
        rule_skip "no changes to check"
        return 3
    fi

    # -------------------------------------------------------------------------
    # Built-in patterns, grouped by language
    # Format: "LABEL|REGEX"
    # Regex is matched against added lines (^\+[^+]...) from the diff.
    # ^\+[^+] matches a single leading + but not the +++ file header lines.
    # -------------------------------------------------------------------------
    local -a patterns=(

        # ── JavaScript / TypeScript ───────────────────────────────────────────
        "JS console|^\+[^+].*\bconsole\.(log|warn|error|info|debug|dir|dirxml|table|trace|group|groupEnd|time|timeEnd|assert|count|profile|profileEnd)\s*\("
        "JS debugger|^\+[^+].*\bdebugger\s*;"
        "JS alert|^\+[^+].*\balert\s*\("

        # ── Python ────────────────────────────────────────────────────────────
        "Python print|^\+[^+].*\bprint\s*\("
        "Python pdb|^\+[^+].*\b(import\s+pdb|pdb\.set_trace|breakpoint)\s*\(?"
        "Python icecream|^\+[^+].*\bic\s*\("

        # ── PHP ───────────────────────────────────────────────────────────────
        "PHP var_dump|^\+[^+].*\bvar_dump\s*\("
        "PHP print_r|^\+[^+].*\bprint_r\s*\("
        "PHP dd/dump|^\+[^+].*\b(dd|dump|ray)\s*\("

        # ── Ruby ──────────────────────────────────────────────────────────────
        "Ruby binding|^\+[^+].*\b(binding\.pry|binding\.irb|byebug)\b"
        "Ruby puts debug|^\+[^+].*\bputs\s+(\"DEBUG|'DEBUG)"

        # ── Go ────────────────────────────────────────────────────────────────
        "Go fmt.Print|^\+[^+].*\bfmt\.(Print|Printf|Println)\s*\("
        "Go spew|^\+[^+].*\bspew\.(Dump|Sdump|Printf)\s*\("

        # ── Java / Kotlin ─────────────────────────────────────────────────────
        "Java println|^\+[^+].*\bSystem\.out\.(print|println|printf)\s*\("
        "Java log debug|^\+[^+].*\b(Log\.d|Log\.v|logger\.debug)\s*\("

        # ── Rust ──────────────────────────────────────────────────────────────
        "Rust dbg!|^\+[^+].*\bdbg!\s*\("
        "Rust eprintln!|^\+[^+].*\beprintln!\s*\("

        # ── Shell ─────────────────────────────────────────────────────────────
        "Shell set -x|^\+[^+].*\bset\s+-x\b"

        # ── Generic markers ───────────────────────────────────────────────────
        "Debug marker|^\+[^+].*(DEBUG_START|DEBUG_END|DEBUG_ONLY|REMOVE_BEFORE_COMMIT)"
    )

    # -------------------------------------------------------------------------
    # Custom patterns from config
    # Example: pattern_no_debug=trace_me\(,MY_DEBUG\(
    # -------------------------------------------------------------------------
    local custom_patterns
    custom_patterns="$(config_get_pattern no_debug)"
    if [[ -n "$custom_patterns" ]]; then
        IFS=',' read -ra custom <<< "$custom_patterns"
        for cp in "${custom[@]}"; do
            cp="$(trim "$cp")"
            [[ -n "$cp" ]] && patterns+=("Custom|^\+[^+].*${cp}")
        done
    fi

    # -------------------------------------------------------------------------
    # File suffixes/substrings to exclude from checking.
    # Default covers the most common test file naming conventions.
    # Override with: no_debug_exclude=.test.js,.spec.py,_integration_test.go
    # -------------------------------------------------------------------------
    local exclude_raw
    exclude_raw="$(config_get no_debug_exclude \
        '.test.js,.spec.js,.test.ts,.spec.ts,.test.jsx,.spec.jsx,_test.go,_test.py,test_.py,_spec.rb,_test.php')"

    # -------------------------------------------------------------------------
    # Walk the unified diff, tracking the current filename (+++ b/...)
    # so we can skip test files before collecting added lines.
    # -------------------------------------------------------------------------
    local added_lines=""
    local skip_file=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^\+\+\+\ b/(.+)$ ]]; then
            local current_file="${BASH_REMATCH[1]}"
            skip_file=0

            if [[ -n "$exclude_raw" ]]; then
                IFS=',' read -ra excl <<< "$exclude_raw"
                for ext in "${excl[@]}"; do
                    ext="$(trim "$ext")"
                    if [[ -n "$ext" && "$current_file" == *"$ext"* ]]; then
                        skip_file=1
                        break
                    fi
                done
            fi
            continue
        fi

        # Collect non-header added lines from non-skipped files
        if [[ $skip_file -eq 0 && "$line" =~ ^\+[^+] ]]; then
            added_lines+="$line"$'\n'
        fi
    done <<< "$diff"

    if [[ -z "$added_lines" ]]; then
        rule_pass "no added lines to check"
        return 0
    fi

    # -------------------------------------------------------------------------
    # Match every pattern against the collected added lines
    # -------------------------------------------------------------------------
    local found=0
    declare -A findings_by_label=()
    local -a finding_lines=()

    for entry in "${patterns[@]}"; do
        local label="${entry%%|*}"
        local pattern="${entry#*|}"
        [[ -z "$pattern" ]] && continue

        local matches
        if matches="$(echo "$added_lines" | grep -E "$pattern" 2>/dev/null)"; then
            found=1
            local match_count
            match_count="$(echo "$matches" | grep -c . || true)"
            findings_by_label["$label"]="$match_count"

            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue
                if [[ ${#finding_lines[@]} -lt 5 ]]; then
                    # Strip leading '+' and truncate for display
                    finding_lines+=("[${label}] ${match_line:1:74}")
                fi
            done <<< "$matches"
        fi
    done

    if [[ $found -eq 0 ]]; then
        rule_pass
        return 0
    fi

    # -------------------------------------------------------------------------
    # Build a compact summary line, e.g. "JS console ×3, Python pdb ×1"
    # -------------------------------------------------------------------------
    local -a summary_parts=()
    for label in "${!findings_by_label[@]}"; do
        local cnt="${findings_by_label[$label]}"
        if [[ "$cnt" -gt 1 ]]; then
            summary_parts+=("${label} ×${cnt}")
        else
            summary_parts+=("${label}")
        fi
    done
    local summary
    # Sort for deterministic output
    summary="$(printf '%s\n' "${summary_parts[@]}" | sort | paste -sd ', ')"

    # -------------------------------------------------------------------------
    # Emit result — warn or fail depending on config
    # -------------------------------------------------------------------------
    local warn_mode
    warn_mode="$(config_get no_debug_warn '0')"

    if [[ "$warn_mode" == "1" ]]; then
        rule_warn "$summary"
    else
        rule_fail "$summary"
    fi

    # Print up to 5 example lines
    for line in "${finding_lines[@]}"; do
        echo -e "      ${DIM}${line}${NC}"
    done

    local total_labels=${#findings_by_label[@]}
    if [[ $total_labels -gt 5 ]]; then
        echo -e "      ${DIM}... and $((total_labels - 5)) more type(s)${NC}"
    fi

    [[ "$warn_mode" == "1" ]] && return 2
    return 1
}