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
# Config value cleaning
#------------------------------------------------------------------------------

# Turns the raw right-hand side of a `key=value` line into the value itself.
#
# This used to be `echo "$value" | sed 's/#.*$//' | xargs`, and both stages
# were wrong in a way nothing reported:
#
#   xargs applies shell word-splitting and quote processing to text that is
#   not a shell word. It ate the escapes out of every pattern before the
#   pattern was ever compiled — `st\.` became `st.` (any character, hence the
#   false positive on `const runway…`), `\s` became a literal `s`, and
#   `['\"]?` lost its single-quote alternative, so `aws_secret_access_key='…'`
#   simply stopped being detected. Which characters survived depended on the
#   quote parity earlier in the line, so the damage was not even consistent.
#   On an unbalanced quote, xargs aborts and the value lands empty.
#
#   `sed 's/#.*$//'` truncates at the first `#` anywhere, so a pattern like
#   `^#!/bin/bash$` was deleted rather than de-commented.
#
# A comment now has to be introduced by whitespace, which is the usual
# convention and leaves a `#` inside a value alone. Trimming is done by the
# repository's own trim(), which is pure parameter expansion and touches
# nothing else — the rest of the codebase already used it.
_config_clean_value() {
    local raw="$1"
    # Strip an inline comment: whitespace followed by # and the rest of line.
    raw="${raw%%[[:space:]]#*}"
    trim "$raw"
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
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse key=value
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Trim trailing comments and whitespace
            value="$(_config_clean_value "$value")"
            
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

    # Validate fail_on
    case "$GITKEEPER_FAIL_ON" in
        error|warn) ;;
        *) log_warn "Unknown fail_on value: '$GITKEEPER_FAIL_ON', defaulting to 'error'"
           GITKEEPER_FAIL_ON="error" ;;
    esac
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

#------------------------------------------------------------------------------
# Per-directory config support
#------------------------------------------------------------------------------

# Find the nearest .gitkeeper.conf for a given file path (relative to repo root).
# Searches from the file's directory upward, stopping at repo root.
# Does NOT return the root config itself — only configs deeper than it.
# Usage: find_dir_config_for_file "src/api/routes.js" "/path/to/repo" "/path/to/repo/.gitkeeper.conf"
find_dir_config_for_file() {
    local file_path="$1"
    local repo_root="$2"
    local root_config="${3:-}"

    local dir
    dir="$(dirname "$file_path")"

    # Walk upward from the file's directory until we reach the repo root
    while [[ "$dir" != "." && "$dir" != "" ]]; do
        local candidate="$repo_root/$dir/$GITKEEPER_CONFIG_NAME"
        if [[ -f "$candidate" && "$candidate" != "$root_config" ]]; then
            echo "$candidate"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    return 1  # no subdirectory config found — use root
}

# Apply a config file as an overlay on top of the currently loaded config.
# Only keys explicitly set in the overlay file are updated; everything else
# inherits from the previously parsed root config.
apply_config_overlay() {
    local overlay_file="$1"

    if [[ ! -f "$overlay_file" ]]; then
        return 0
    fi

    log_debug "config: applying overlay $overlay_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value
            value="$(_config_clean_value "${BASH_REMATCH[2]}")"

            GITKEEPER_CONFIG["$key"]="$value"

            case "$key" in
                rules)         GITKEEPER_RULES="$value" ;;
                fail_on)       GITKEEPER_FAIL_ON="$value" ;;
                check_stash)   GITKEEPER_CHECK_STASH="$value" ;;
                stash_fail_on) GITKEEPER_STASH_FAIL_ON="$value" ;;
            esac

            log_debug "config overlay: $key = $value"
        fi
    done < "$overlay_file"
}
