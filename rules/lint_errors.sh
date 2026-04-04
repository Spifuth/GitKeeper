#!/usr/bin/env bash
#
# Rule: lint_errors
# Run the appropriate linter for each staged file extension.
# Fails on linter errors; warns (never fails) if a linter binary is missing
# unless lint_errors_fail_on_missing=1 is set.
#
# Config keys:
#   lint_errors_tools=shellcheck,eslint,flake8,rubocop,go
#       Comma list of tools to enable. Default: all.
#   lint_errors_fail_on_missing=0
#       Set 1 to fail when a configured tool is not installed.
#   lint_errors_args_<tool>=<args>
#       Override default CLI args for a specific tool.
#       e.g. lint_errors_args_shellcheck=--severity=warning
#

# ---------------------------------------------------------------------------
# Module-level helpers (defined at source time, prefixed _lint_ to avoid
# collisions with other rules).
# ---------------------------------------------------------------------------

# Resolve effective args for a linter tool.
# Usage: _lint_get_args <tool> <built-in-default>
_lint_get_args() {
    local tool="$1"
    local builtin_default="$2"
    local override
    override="$(config_get "lint_errors_args_${tool}" "")"
    echo "${override:-$builtin_default}"
}

# ---------------------------------------------------------------------------
# Rule
# ---------------------------------------------------------------------------

rule_lint_errors() {
    local scope="$1"
    set_current_rule "lint_errors"

    local files
    files="$(get_scope_files "$scope")"

    if [[ -z "$files" ]]; then
        rule_skip "no files to check"
        return 3
    fi

    # ── Config ────────────────────────────────────────────────────────────────
    local tools_cfg
    tools_cfg="$(config_get lint_errors_tools "shellcheck,eslint,flake8,rubocop,go")"

    local fail_on_missing
    fail_on_missing="$(config_get lint_errors_fail_on_missing "0")"

    # ── Build enabled-tools lookup ────────────────────────────────────────────
    local -A enabled=()
    local _t
    IFS=',' read -ra _tlist <<< "$tools_cfg"
    for _t in "${_tlist[@]}"; do
        _t="$(trim "$_t")"
        [[ -n "$_t" ]] && enabled["$_t"]=1
    done

    # ── Group staged files by linter ──────────────────────────────────────────
    local -a sh_files=()
    local -a js_files=()
    local -a ts_files=()
    local -a py_files=()
    local -a rb_files=()
    local -a go_files=()

    while IFS= read -r file; do
        [[ -z "$file" || ! -f "$file" ]] && continue
        case "$file" in
            *.sh|*.bash)             sh_files+=("$file") ;;
            *.js|*.mjs|*.cjs|*.jsx)  js_files+=("$file") ;;
            *.ts|*.tsx)              ts_files+=("$file") ;;
            *.py)                    py_files+=("$file") ;;
            *.rb)                    rb_files+=("$file") ;;
            *.go)                    go_files+=("$file") ;;
        esac
    done <<< "$files"

    local total_lintable=$(( ${#sh_files[@]} + ${#js_files[@]} + ${#ts_files[@]} \
                            + ${#py_files[@]} + ${#rb_files[@]} + ${#go_files[@]} ))
    if [[ $total_lintable -eq 0 ]]; then
        rule_skip "no lintable files in scope"
        return 3
    fi

    # ── Shared state for results ──────────────────────────────────────────────
    local overall_failed=0
    local -a summary_parts=()   # e.g. "shellcheck (2 files)"
    local -a error_lines=()     # up to 5 lines per tool, prefixed [tool]

    # ── _check_binary: verify a tool exists ──────────────────────────────────
    # Returns 0 if found, 1 if missing (and handles warn/fail per config).
    _check_binary() {
        local tool="$1"
        if command -v "$tool" &>/dev/null; then
            return 0
        fi
        if [[ "$fail_on_missing" == "1" ]]; then
            error_lines+=("  [missing] $tool is not installed (lint_errors_fail_on_missing=1)")
            overall_failed=1
        else
            log_warn "lint_errors: $tool not found, skipping"
        fi
        return 1
    }

    # ── _run_linter: execute a linter and collect failures ───────────────────
    # Usage: _run_linter <tool-label> <n-files> <args-string> <file> [<file>…]
    _run_linter() {
        local label="$1"
        local nfiles="$2"
        local args_str="$3"
        shift 3

        log_debug "lint: $label $args_str $*"

        local output exit_code=0
        # args_str is intentionally word-split here (it's a CLI flags string)
        # shellcheck disable=SC2086
        output="$( "$label" $args_str "$@" 2>&1 )" || exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            summary_parts+=("$label ($nfiles file(s))")
            overall_failed=1
            local count=0
            while IFS= read -r _line; do
                [[ $count -ge 5 ]] && break
                [[ -z "$(trim "$_line")" ]] && continue
                error_lines+=("  [$label] $_line")
                (( count++ )) || true
            done <<< "$output"
            local total_lines
            total_lines="$( printf '%s\n' "$output" | grep -c . 2>/dev/null || true )"
            if (( total_lines > 5 )); then
                error_lines+=("  [$label] … $(( total_lines - 5 )) more line(s)")
            fi
        fi
    }

    # ── shellcheck ────────────────────────────────────────────────────────────
    if [[ ${#sh_files[@]} -gt 0 && -n "${enabled[shellcheck]:-}" ]]; then
        if _check_binary shellcheck; then
            local sc_args
            sc_args="$(_lint_get_args shellcheck "--severity=error")"
            _run_linter shellcheck "${#sh_files[@]}" "$sc_args" "${sh_files[@]}"
        fi
    fi

    # ── eslint  (JS + TS together) ────────────────────────────────────────────
    local -a eslint_files=( "${js_files[@]}" "${ts_files[@]}" )
    if [[ ${#eslint_files[@]} -gt 0 && -n "${enabled[eslint]:-}" ]]; then
        if _check_binary eslint; then
            local eslint_args
            eslint_args="$(_lint_get_args eslint "--max-warnings=0")"
            _run_linter eslint "${#eslint_files[@]}" "$eslint_args" "${eslint_files[@]}"
        fi
    fi

    # ── flake8 ────────────────────────────────────────────────────────────────
    if [[ ${#py_files[@]} -gt 0 && -n "${enabled[flake8]:-}" ]]; then
        if _check_binary flake8; then
            local flake8_args
            flake8_args="$(_lint_get_args flake8 "--select=E9,F63,F7,F82")"
            _run_linter flake8 "${#py_files[@]}" "$flake8_args" "${py_files[@]}"
        fi
    fi

    # ── rubocop ───────────────────────────────────────────────────────────────
    if [[ ${#rb_files[@]} -gt 0 && -n "${enabled[rubocop]:-}" ]]; then
        if _check_binary rubocop; then
            local rubocop_args
            rubocop_args="$(_lint_get_args rubocop "--only Lint")"
            _run_linter rubocop "${#rb_files[@]}" "$rubocop_args" "${rb_files[@]}"
        fi
    fi

    # ── go vet  (per module root, never per-file) ─────────────────────────────
    if [[ ${#go_files[@]} -gt 0 && -n "${enabled[go]:-}" ]]; then
        if _check_binary go; then
            # Collect unique module roots by walking up to the nearest go.mod.
            local -A go_roots=()
            local _gf _dir _mroot
            for _gf in "${go_files[@]}"; do
                _dir="$(dirname "$_gf")"
                _mroot="$_dir"
                while [[ "$_mroot" != "." && "$_mroot" != "/" ]]; do
                    [[ -f "$_mroot/go.mod" ]] && break
                    _mroot="$(dirname "$_mroot")"
                done
                if [[ -f "$_mroot/go.mod" ]]; then
                    go_roots["$_mroot"]=1
                else
                    go_roots["$_dir"]=1   # no go.mod found; use file's directory
                fi
            done

            local _root
            for _root in "${!go_roots[@]}"; do
                log_debug "lint: go vet ./... in $_root"
                local go_out go_exit=0
                go_out="$( cd "$_root" && go vet ./... 2>&1 )" || go_exit=$?
                if [[ $go_exit -ne 0 ]]; then
                    summary_parts+=("go (${#go_files[@]} file(s))")
                    overall_failed=1
                    local _gc=0
                    while IFS= read -r _line; do
                        [[ $_gc -ge 5 ]] && break
                        [[ -z "$(trim "$_line")" ]] && continue
                        error_lines+=("  [go vet] $_line")
                        (( _gc++ )) || true
                    done <<< "$go_out"
                fi
            done
        fi
    fi

    # ── Result ────────────────────────────────────────────────────────────────
    if [[ $overall_failed -ne 0 ]]; then
        local summary_str
        # Join summary_parts with ", "
        summary_str="$( IFS=', '; echo "${summary_parts[*]}" )"
        rule_fail "${summary_str:-lint errors found}"
        local _eline
        for _eline in "${error_lines[@]}"; do
            echo -e "      ${DIM}${_eline:0:100}${NC}"
        done
        return 1
    fi

    rule_pass
    return 0
}
