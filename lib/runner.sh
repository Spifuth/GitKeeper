#!/usr/bin/env bash
#
# GitKeeper - Rule runner
# Load and execute rules
#

# Directory containing rule scripts (resolved at load time)
GITKEEPER_RULES_DIR="${GITKEEPER_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}/rules"

#------------------------------------------------------------------------------
# Rule discovery
#------------------------------------------------------------------------------

# List all available rules
list_available_rules() {
    local rules_dir="$GITKEEPER_RULES_DIR"
    
    if [[ -d "$rules_dir" ]]; then
        for rule_file in "$rules_dir"/*.sh; do
            if [[ -f "$rule_file" ]]; then
                basename "$rule_file" .sh
            fi
        done
    fi
}

# Check if a rule exists
rule_exists() {
    local rule="$1"
    local rule_file="$GITKEEPER_RULES_DIR/${rule}.sh"
    
    [[ -f "$rule_file" ]]
}

# Get rule file path
get_rule_file() {
    local rule="$1"
    echo "$GITKEEPER_RULES_DIR/${rule}.sh"
}

#------------------------------------------------------------------------------
# Rule execution
#------------------------------------------------------------------------------

# Load a rule (source its file)
load_rule() {
    local rule="$1"
    local rule_file
    rule_file="$(get_rule_file "$rule")"
    
    if [[ ! -f "$rule_file" ]]; then
        log_warn "rule not found: $rule"
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$rule_file"
}

# Run a single rule
# Returns: 0 = pass, 1 = fail, 2 = warn, 3 = skip
run_rule() {
    local rule="$1"
    local scope="$2"
    
    log_debug "runner: executing rule '$rule' with scope '$scope'"
    
    # Load rule if not already loaded
    if ! declare -f "rule_${rule}" &>/dev/null; then
        if ! load_rule "$rule"; then
            log_rule "$rule" skip "not found"
            return 3
        fi
    fi
    
    # Check if rule function exists
    if ! declare -f "rule_${rule}" &>/dev/null; then
        log_warn "rule '$rule' has no rule_${rule} function"
        return 3
    fi
    
    # Execute rule
    local result=0
    "rule_${rule}" "$scope" || result=$?
    
    return $result
}

# Run all configured rules
run_all_rules() {
    local scope="$1"
    local rules_string
    rules_string="$(config_get_rules)"
    
    local total=0
    local passed=0
    local warned=0
    local failed=0
    local skipped=0
    
    # Parse comma-separated rules
    IFS=',' read -ra rules <<< "$rules_string"
    
    for rule in "${rules[@]}"; do
        rule="$(trim "$rule")"
        [[ -z "$rule" ]] && continue
        
        ((total++)) || true
        
        local result=0
        run_rule "$rule" "$scope" || result=$?
        
        case $result in
            0) ((passed++)) || true ;;
            1) ((failed++)) || true; export GITKEEPER_HAS_ERRORS=1 ;;
            2) ((warned++)) || true; export GITKEEPER_HAS_WARNINGS=1 ;;
            3) ((skipped++)) || true ;;
        esac
    done
    
    # Return summary via global variables (output is used by rules)
    export GITKEEPER_SUMMARY_TOTAL=$total
    export GITKEEPER_SUMMARY_PASSED=$passed
    export GITKEEPER_SUMMARY_WARNED=$warned
    export GITKEEPER_SUMMARY_FAILED=$failed
    export GITKEEPER_SUMMARY_SKIPPED=$skipped
}

#------------------------------------------------------------------------------
# Rule helpers (available to rule scripts)
#------------------------------------------------------------------------------

# Standard rule result handlers
rule_pass() {
    local msg="${1:-}"
    log_rule "${CURRENT_RULE:-unknown}" pass "$msg"
    return 0
}

rule_warn() {
    local msg="${1:-}"
    log_rule "${CURRENT_RULE:-unknown}" warn "$msg"
    export GITKEEPER_HAS_WARNINGS=1
    return 2
}

rule_fail() {
    local msg="${1:-}"
    log_rule "${CURRENT_RULE:-unknown}" fail "$msg"
    export GITKEEPER_HAS_ERRORS=1
    return 1
}

rule_skip() {
    local msg="${1:-}"
    log_rule "${CURRENT_RULE:-unknown}" skip "$msg"
    return 3
}

# Set current rule context (for logging)
set_current_rule() {
    export CURRENT_RULE="$1"
}
