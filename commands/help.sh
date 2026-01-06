#!/usr/bin/env bash
#
# GitKeeper - help command
# Display usage information
#

GITKEEPER_VERSION="1.0.0"

cmd_version() {
    echo "gitkeeper version $GITKEEPER_VERSION"
}

cmd_help() {
    cat << EOF
${BOLD}GitKeeper${NC} — Git repository quality gate

${BOLD}USAGE${NC}
    gitkeeper <command> [options]

${BOLD}COMMANDS${NC}
    check             Run rules on a scope
    init              Generate a starter config file
    configure         Interactive configuration wizard
    install-hooks     Install pre-commit and pre-push hooks
    uninstall-hooks   Remove hooks configuration
    explain           Show what will be checked (debug mode)
    version           Show version information
    help              Show this help message

${BOLD}CHECK OPTIONS${NC}
    --scope <scope>   What to check:
                        staged       Files staged for commit (default)
                        push         Commits to be pushed
                        pr           PR/MR diff (for CI)
                        stash        Stash contents
                        range:X..Y   Custom git range
    -v, --verbose     Enable verbose output
    -q, --quiet       Minimal output

${BOLD}GLOBAL OPTIONS${NC}
    --config <file>   Path to config file (default: .gitkeeper.conf)

${BOLD}EXIT CODES${NC}
    0   OK — all checks passed
    1   Warnings (only fails if fail_on=warn)
    2   Errors — checks failed

${BOLD}EXAMPLES${NC}
    gitkeeper init                    # Create config file
    gitkeeper configure               # Interactive setup wizard
    gitkeeper install-hooks           # Set up git hooks
    gitkeeper check                   # Check staged files
    gitkeeper check --scope push      # Check commits to push
    gitkeeper check --scope pr        # Check PR diff (CI)
    gitkeeper explain --scope staged  # Preview what will run

${BOLD}CONFIG FILE${NC}
    Default: .gitkeeper.conf

    rules=secrets,forbid_files,changelog
    fail_on=error
    pattern_secrets=CUSTOM_[A-Z]+

${BOLD}MORE INFO${NC}
    https://github.com/your-org/gitkeeper
EOF
}
