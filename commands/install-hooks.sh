#!/usr/bin/env bash
#
# GitKeeper - install-hooks command
# Install git hooks for automatic checking
#

cmd_install_hooks() {
    local hooks_dir=".githooks"
    local link_mode=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hooks-dir)
                hooks_dir="$2"
                shift 2
                ;;
            --hooks-dir=*)
                hooks_dir="${1#--hooks-dir=}"
                shift
                ;;
            --link)
                link_mode=1
                shift
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
    
    # Create hooks directory
    mkdir -p "$hooks_dir"
    
    # Determine gitkeeper path
    local gitkeeper_cmd
    if [[ -n "${GITKEEPER_BIN:-}" ]]; then
        gitkeeper_cmd="$GITKEEPER_BIN"
    elif [[ -x "./gitkeeper" ]]; then
        gitkeeper_cmd="\$(git rev-parse --show-toplevel)/gitkeeper"
    else
        gitkeeper_cmd="gitkeeper"
    fi
    
    # Create pre-commit hook
    cat > "$hooks_dir/pre-commit" << EOF
#!/usr/bin/env bash
#
# GitKeeper pre-commit hook
# Runs: gitkeeper check --scope staged
#

set -euo pipefail

# Find gitkeeper
GITKEEPER="${gitkeeper_cmd}"
if [[ ! -x "\$GITKEEPER" ]] && ! command -v gitkeeper &>/dev/null; then
    if [[ -x "\$(git rev-parse --show-toplevel)/gitkeeper" ]]; then
        GITKEEPER="\$(git rev-parse --show-toplevel)/gitkeeper"
    else
        echo "Error: gitkeeper not found" >&2
        exit 1
    fi
fi

exec "\$GITKEEPER" check --scope staged
EOF
    chmod +x "$hooks_dir/pre-commit"
    log_success "Created $hooks_dir/pre-commit"
    
    # Create pre-push hook
    cat > "$hooks_dir/pre-push" << EOF
#!/usr/bin/env bash
#
# GitKeeper pre-push hook
# Runs: gitkeeper check --scope push
#

set -euo pipefail

# Find gitkeeper
GITKEEPER="${gitkeeper_cmd}"
if [[ ! -x "\$GITKEEPER" ]] && ! command -v gitkeeper &>/dev/null; then
    if [[ -x "\$(git rev-parse --show-toplevel)/gitkeeper" ]]; then
        GITKEEPER="\$(git rev-parse --show-toplevel)/gitkeeper"
    else
        echo "Error: gitkeeper not found" >&2
        exit 1
    fi
fi

exec "\$GITKEEPER" check --scope push
EOF
    chmod +x "$hooks_dir/pre-push"
    log_success "Created $hooks_dir/pre-push"
    
    # Configure git to use hooks directory
    git config core.hooksPath "$hooks_dir"
    log_success "Configured core.hooksPath = $hooks_dir"
    
    echo ""
    log_info "Hooks installed! They will run automatically."
    echo ""
    echo "Hook mapping:"
    echo "  pre-commit → gitkeeper check --scope staged"
    echo "  pre-push   → gitkeeper check --scope push"
    echo ""
    echo "To uninstall:"
    echo "  git config --unset core.hooksPath"
}

cmd_uninstall_hooks() {
    git config --unset core.hooksPath 2>/dev/null || true
    log_success "Removed core.hooksPath config"
    log_info "Hooks directory not deleted (manual cleanup if needed)"
}
