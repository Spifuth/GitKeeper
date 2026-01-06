#!/usr/bin/env bash
#
# Rule: secrets
# Detect leaked secrets, API keys, tokens, and passwords
#

rule_secrets() {
    local scope="$1"
    set_current_rule "secrets"
    
    local diff
    diff="$(get_scope_diff "$scope")"
    
    if [[ -z "$diff" ]]; then
        rule_skip "no changes to check"
        return 3
    fi
    
    # Built-in patterns for common secrets
    local -a patterns=(
        # AWS
        'AKIA[0-9A-Z]{16}'
        'ASIA[0-9A-Z]{16}'
        
        # OpenAI
        'sk-[a-zA-Z0-9]{48}'
        
        # Stripe
        'sk_live_[a-zA-Z0-9]{24,}'
        'rk_live_[a-zA-Z0-9]{24,}'
        
        # GitHub
        'ghp_[a-zA-Z0-9]{36}'
        'gho_[a-zA-Z0-9]{36}'
        'ghu_[a-zA-Z0-9]{36}'
        'ghs_[a-zA-Z0-9]{36}'
        'ghr_[a-zA-Z0-9]{36}'
        
        # GitLab
        'glpat-[a-zA-Z0-9\-]{20}'
        
        # Slack
        'xox[baprs]-[a-zA-Z0-9\-]{10,}'
        
        # Private keys
        '-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY'
        
        # Generic patterns (high confidence)
        'password\s*[:=]\s*["\x27][^"\x27\s]{8,}["\x27]'
        'api[_-]?key\s*[:=]\s*["\x27][a-zA-Z0-9_\-]{20,}["\x27]'
        'secret\s*[:=]\s*["\x27][^"\x27\s]{8,}["\x27]'
        'token\s*[:=]\s*["\x27][a-zA-Z0-9_\-]{20,}["\x27]'
    )
    
    # Add custom patterns from config
    local custom_patterns
    custom_patterns="$(config_get_pattern secrets)"
    if [[ -n "$custom_patterns" ]]; then
        IFS=',' read -ra custom <<< "$custom_patterns"
        patterns+=("${custom[@]}")
    fi
    
    # Check diff for patterns
    local found=0
    local findings=()
    
    for pattern in "${patterns[@]}"; do
        pattern="$(trim "$pattern")"
        [[ -z "$pattern" ]] && continue
        
        # Only check added lines (starting with +)
        local matches
        if matches="$(echo "$diff" | grep -E '^\+' | grep -Ei "$pattern" 2>/dev/null)"; then
            found=1
            while IFS= read -r line; do
                # Truncate for display
                findings+=("${line:0:80}")
            done <<< "$matches"
        fi
    done
    
    if [[ $found -eq 1 ]]; then
        rule_fail "potential secrets detected"
        for finding in "${findings[@]:0:5}"; do
            echo -e "      ${DIM}${finding}${NC}"
        done
        if [[ ${#findings[@]} -gt 5 ]]; then
            echo -e "      ${DIM}... and $((${#findings[@]} - 5)) more${NC}"
        fi
        return 1
    fi
    
    rule_pass
    return 0
}
