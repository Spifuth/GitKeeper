#!/usr/bin/env bash
#
# GitKeeper - init command
# Generate a starter config file
#

cmd_init() {
    local force=0
    local output="$GITKEEPER_CONFIG_NAME"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                force=1
                shift
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
    
    # Check if config already exists
    if [[ -f "$output" && $force -eq 0 ]]; then
        die "config already exists: $output (use --force to overwrite)"
    fi
    
    # Generate config
    cat > "$output" << 'EOF'
# GitKeeper Configuration
# https://github.com/your-org/gitkeeper

# ─────────────────────────────────────────────────────────────────────────────
# Rules
# ─────────────────────────────────────────────────────────────────────────────

# Comma-separated list of rules to run
# Available: secrets, forbid_files, changelog, version, readme, todos,
#            branch_name, large_files, merge_conflict
rules=secrets,forbid_files,merge_conflict,large_files

# ─────────────────────────────────────────────────────────────────────────────
# Behavior
# ─────────────────────────────────────────────────────────────────────────────

# When to fail: error | warn
fail_on=error

# Stash checking (optional audit mode)
check_stash=0
stash_fail_on=warn

# ─────────────────────────────────────────────────────────────────────────────
# Rule Parameters
# ─────────────────────────────────────────────────────────────────────────────

# Custom patterns for secret detection (comma-separated regex)
# pattern_secrets=CUSTOM_API_[A-Z0-9]{32},MY_SECRET_[a-z]+

# Forbidden file patterns (comma-separated regex)
# pattern_forbid_files=\.secret$,private/.*

# Branch naming convention (regex)
# pattern_branch_name=(feature|bugfix|hotfix|release|chore)/[a-z0-9-]+

# Max file size in bytes (default: 5MB = 5242880)
# pattern_large_files=10485760

# File patterns that trigger changelog requirement
# trigger_changelog=\.(js|ts|py|go|rs|java|rb|php)$

# Version files to check for updates
# required_version=package.json,version.txt,VERSION
EOF

    log_success "Created $output"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $output to customize rules"
    echo "  2. Run: gitkeeper install-hooks"
    echo "  3. Commit your changes"
}
