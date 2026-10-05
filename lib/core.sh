#!/usr/bin/env bash
#
# GitKeeper - Core utilities
# Logging, colors, and shared functions
#

# Exit codes
export EXIT_OK=0
export EXIT_WARN=1
export EXIT_ERROR=2

# Colors (disable if not a terminal)
if [[ -t 1 ]]; then
    export RED='\033[0;31m'
    export YELLOW='\033[1;33m'
    export GREEN='\033[0;32m'
    export BLUE='\033[0;34m'
    export CYAN='\033[0;36m'
    export BOLD='\033[1m'
    export DIM='\033[2m'
    export NC='\033[0m'
else
    export RED='' YELLOW='' GREEN='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# Global state
export GITKEEPER_VERBOSE="${GITKEEPER_VERBOSE:-0}"
# Quiet mode (`check -q`): only warnings, failures and their details are
# printed. Errors always reach the user, and exit codes are unaffected.
export GITKEEPER_QUIET="${GITKEEPER_QUIET:-0}"
export GITKEEPER_HAS_WARNINGS=0
export GITKEEPER_HAS_ERRORS=0

#------------------------------------------------------------------------------
# Logging
#------------------------------------------------------------------------------

is_quiet() {
    [[ "${GITKEEPER_QUIET:-0}" -eq 1 ]]
}

log_info() {
    is_quiet && return 0
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    is_quiet && return 0
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    export GITKEEPER_HAS_WARNINGS=1
}

log_error() {
    echo -e "${RED}✗${NC} $*"
    export GITKEEPER_HAS_ERRORS=1
}

log_debug() {
    if [[ "$GITKEEPER_VERBOSE" -eq 1 ]]; then
        echo -e "${DIM}»${NC} $*"
    fi
}

log_rule() {
    local rule="$1"
    local status="$2"
    local msg="${3:-}"
    
    case "$status" in
        pass)
            is_quiet && return 0
            echo -e "  ${GREEN}✓${NC} ${rule}${msg:+ — $msg}"
            ;;
        warn)
            echo -e "  ${YELLOW}⚠${NC} ${rule}${msg:+ — $msg}"
            ;;
        fail)
            echo -e "  ${RED}✗${NC} ${rule}${msg:+ — $msg}"
            ;;
        skip)
            is_quiet && return 0
            echo -e "  ${DIM}○${NC} ${rule}${msg:+ — $msg}"
            ;;
    esac
}

die() {
    echo -e "${RED}error:${NC} $*" >&2
    exit "$EXIT_ERROR"
}

print_header() {
    is_quiet && return 0
    echo -e "${BOLD}$*${NC}"
}

# Blank spacer line between output sections; suppressed in quiet mode.
print_blank() {
    is_quiet && return 0
    echo ""
}

print_separator() {
    is_quiet && return 0
    echo -e "${DIM}─────────────────────────────────────────${NC}"
}

#------------------------------------------------------------------------------
# Utilities
#------------------------------------------------------------------------------

# Check if we're in a git repository
require_git_repo() {
    if ! git rev-parse --git-dir &>/dev/null; then
        die "not a git repository"
    fi
}

# Get repository root
get_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Trim whitespace
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Check if array contains element
array_contains() {
    local needle="$1"
    shift
    for element in "$@"; do
        [[ "$element" == "$needle" ]] && return 0
    done
    return 1
}
