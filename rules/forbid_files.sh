#!/usr/bin/env bash
#
# Rule: forbid_files
# Block sensitive or forbidden file types
#

# True when the basename of $1 is exactly an env template name.
_forbid_files_is_env_template() {
    local name="${1##*/}"
    [[ "$name" == ".env.example" || "$name" == ".env.sample" || "$name" == ".env.template" ]]
}

rule_forbid_files() {
    local scope="$1"
    set_current_rule "forbid_files"
    
    local files
    files="$(get_scope_files "$scope")"
    
    if [[ -z "$files" ]]; then
        rule_skip "no files to check"
        return 3
    fi
    
    # Built-in forbidden patterns
    local -a patterns=(
        # Environment files
        '\.env$'
        '\.env\.[a-z]+$'
        
        # SSH keys
        'id_rsa$'
        'id_dsa$'
        'id_ecdsa$'
        'id_ed25519$'
        '\.pem$'
        
        # Certificates and keystores
        '\.key$'
        '\.p12$'
        '\.pfx$'
        '\.jks$'
        '\.keystore$'
        
        # Credentials
        'credentials\.json$'
        'service[_-]?account.*\.json$'
        '\.htpasswd$'
        '\.netrc$'
        
        # System files
        'shadow$'
        'passwd$'
        
        # IDE/Editor secrets
        '\.idea/.*tokens'
        '\.vscode/.*secret'
    )
    
    # Add custom patterns from config
    local custom_patterns
    custom_patterns="$(config_get_pattern forbid_files)"
    if [[ -n "$custom_patterns" ]]; then
        IFS=',' read -ra custom <<< "$custom_patterns"
        patterns+=("${custom[@]}")
    fi
    
    # Check files against patterns
    local found=0
    local forbidden_files=()
    local subject
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # An env TEMPLATE is the one `.env.*` file that is meant to be tracked:
        # it holds placeholders, and every repo is expected to commit one. But
        # both the built-in `\.env\.[a-z]+$` and the shipped `(^|/)\.env\..*`
        # match it, and ERE has no negative lookahead to carve it out of a
        # pattern -- so the carve-out lives here, and it is deliberately narrow:
        #
        #   - three exact basenames, lowercase, nothing else. `.env.local`,
        #     `.env.production`, `.env.example.local` and `app.env.example` are
        #     all still judged by name like any other file;
        #   - only the NAME is exempt. The template is still judged by the
        #     directory it lives in, so `node_modules/x/.env.example` is still
        #     rejected by the directory patterns;
        #   - its CONTENT is not exempt at all: the secrets rule scans the diff
        #     of every file, templates included.
        subject="$file"
        if _forbid_files_is_env_template "$file"; then
            if [[ "$file" == */* ]]; then
                subject="${file%/*}/"
            else
                subject=""
            fi
        fi

        for pattern in "${patterns[@]}"; do
            pattern="$(trim "$pattern")"
            [[ -z "$pattern" ]] && continue
            
            if [[ "$subject" =~ $pattern ]]; then
                found=1
                forbidden_files+=("$file")
                break
            fi
        done
    done <<< "$files"
    
    if [[ $found -eq 1 ]]; then
        rule_fail "${#forbidden_files[@]} forbidden file(s)"
        for f in "${forbidden_files[@]:0:5}"; do
            echo -e "      ${RED}$f${NC}"
        done
        if [[ ${#forbidden_files[@]} -gt 5 ]]; then
            echo -e "      ${DIM}... and $((${#forbidden_files[@]} - 5)) more${NC}"
        fi
        return 1
    fi
    
    rule_pass
    return 0
}
