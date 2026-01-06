#!/usr/bin/env bash
#
# GitKeeper - Configuration management
# Parsing and accessing config values
#

# Default config filename
export GITKEEPER_CONFIG_NAME=".gitkeeper.conf"

# Config state
declare -gA GITKEEPER_CONFIG=()
export GITKEEPER_RULES=""
export GITKEEPER_FAIL_ON="error"
export GITKEEPER_CHECK_STASH=0
export GITKEEPER_STASH_FAIL_ON="warn"

#------------------------------------------------------------------------------
# Config discovery
#------------------------------------------------------------------------------

# Find config file, searching upward from given path
find_config() {
    local search_path="${1:-.}"
    
    # Check explicit config first
    if [[ -n "${GITKEEPER_CONFIG_FILE:-}" ]]; then
        if [[ -f "$GITKEEPER_CONFIG_FILE" ]]; then
            echo "$GITKEEPER_CONFIG_FILE"
            return 0
        else
            die "config file not found: $GITKEEPER_CONFIG_FILE"
        fi
    fi
    
    # Search upward for config
    local dir
    dir="$(cd "$search_path" && pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/$GITKEEPER_CONFIG_NAME" ]]; then
            echo "$dir/$GITKEEPER_CONFIG_NAME"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    
    return 1
}

#------------------------------------------------------------------------------
# Config parsing
#------------------------------------------------------------------------------

# Parse a config file into GITKEEPER_CONFIG associative array
parse_config() {
    local config_file="$1"
    
    # Reset to defaults
    GITKEEPER_RULES="secrets,forbid_files"
    GITKEEPER_FAIL_ON="error"
    GITKEEPER_CHECK_STASH=0
    GITKEEPER_STASH_FAIL_ON="warn"
    
    if [[ ! -f "$config_file" ]]; then
        log_debug "config: using defaults (no config file)"
        return 0
    fi
    
    log_debug "config: loading $config_file"
    
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse key=value
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Trim trailing comments and whitespace
            value="$(echo "$value" | sed 's/#.*$//' | xargs)"
            
            # Store in associative array
            GITKEEPER_CONFIG["$key"]="$value"
            
            # Handle known keys
            case "$key" in
                rules)
                    GITKEEPER_RULES="$value"
                    ;;
                fail_on)
                    GITKEEPER_FAIL_ON="$value"
                    ;;
                check_stash)
                    GITKEEPER_CHECK_STASH="$value"
                    ;;
                stash_fail_on)
                    GITKEEPER_STASH_FAIL_ON="$value"
                    ;;
            esac
            
            log_debug "config: $key = $value"
        fi
    done < "$config_file"
}

#------------------------------------------------------------------------------
# Config accessors
#------------------------------------------------------------------------------

# Get a config value with optional default
config_get() {
    local key="$1"
    local default="${2:-}"
    
    echo "${GITKEEPER_CONFIG[$key]:-$default}"
}

# Get pattern config for a rule
config_get_pattern() {
    local rule="$1"
    local default="${2:-}"
    
    config_get "pattern_${rule}" "$default"
}

# Get trigger config for a rule
config_get_trigger() {
    local rule="$1"
    local default="${2:-}"
    
    config_get "trigger_${rule}" "$default"
}

# Get required files config for a rule
config_get_required() {
    local rule="$1"
    local default="${2:-}"
    
    config_get "required_${rule}" "$default"
}

# Get list of enabled rules
config_get_rules() {
    echo "$GITKEEPER_RULES"
}

# Check if we should fail on warnings
config_fail_on_warn() {
    [[ "$GITKEEPER_FAIL_ON" == "warn" ]]
}
