#!/usr/bin/env bash
#
# Rule: lint_errors
# Run shellcheck on shell scripts, eslint on JS/TS files.
# Skips gracefully if no linter is installed — never blocks a team
# that doesn't use that linter.
#

rule_lint_errors() {
    local scope="$1"
    set_current_rule "lint_errors"

    local files
    files="$(get_scope_files "$scope")"

    if [[ -z "$files" ]]; then
        rule_skip "no files to check"
        return 3
    fi

    # ── Discover available linters ────────────────────────────────────────────
    local has_shellcheck=0
    local has_eslint=0
    command -v shellcheck &>/dev/null && has_shellcheck=1
    command -v eslint     &>/dev/null && has_eslint=1

    if [[ $has_shellcheck -eq 0 && $has_eslint -eq 0 ]]; then
        rule_skip "no linters found (install shellcheck or eslint)"
        return 3
    fi

    # ── Read config ───────────────────────────────────────────────────────────
    # Defaults: shellcheck reports only errors (not style nits),
    # eslint treats any warning as a failure.
    local sc_args eslint_args
    sc_args="$(config_get    lint_shellcheck_args '--severity=error')"
    eslint_args="$(config_get lint_eslint_args    '--max-warnings=0')"

    # ── Run linters ───────────────────────────────────────────────────────────
    local errors=0
    local checked=0
    local -a error_lines=()

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue  # skip deleted files still in diff

        local output=""
        case "$file" in

            *.sh|*.bash)
                [[ $has_shellcheck -eq 0 ]] && continue
                log_debug "lint: shellcheck $file"
                # shellcheck disable=SC2086
                output="$(shellcheck $sc_args "$file" 2>&1)" || {
                    ((errors++)) || true
                    while IFS= read -r line; do
                        error_lines+=("[$file] $line")
                    done <<< "$output"
                }
                ((checked++)) || true
                ;;

            *.js|*.mjs|*.cjs|*.jsx|*.ts|*.tsx)
                [[ $has_eslint -eq 0 ]] && continue
                log_debug "lint: eslint $file"
                # shellcheck disable=SC2086
                output="$(eslint $eslint_args "$file" 2>&1)" || {
                    ((errors++)) || true
                    while IFS= read -r line; do
                        [[ -z "$(trim "$line")" ]] && continue  # skip blank lines
                        error_lines+=("$line")
                    done <<< "$output"
                }
                ((checked++)) || true
                ;;

        esac
    done <<< "$files"

    # ── No lintable files in this scope? ──────────────────────────────────────
    if [[ $checked -eq 0 ]]; then
        rule_skip "no lintable files in scope"
        return 3
    fi

    # ── Report ────────────────────────────────────────────────────────────────
    if [[ $errors -gt 0 ]]; then
        rule_fail "$errors of $checked file(s) failed linting"

        local shown=0
        for line in "${error_lines[@]}"; do
            [[ $shown -ge 8 ]] && break
            echo -e "      ${DIM}${line:0:90}${NC}"
            ((shown++)) || true
        done

        local total="${#error_lines[@]}"
        if [[ $total -gt 8 ]]; then
            echo -e "      ${DIM}... $(( total - 8 )) more — run the linter directly to see all${NC}"
        fi

        return 1
    fi

    rule_pass "$checked file(s) clean"
    return 0
}