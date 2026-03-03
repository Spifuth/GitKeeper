#!/usr/bin/env bash
#
# GitKeeper Installer
# Installs gitkeeper to PATH, sets up completions, and configures shell
#

set -uo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

GITKEEPER_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${GITKEEPER_INSTALL_DIR:-$HOME/.local/bin}"
COMPLETIONS_DIR="${GITKEEPER_COMPLETIONS_DIR:-$HOME/.local/share/bash-completion/completions}"
SHELL_RC=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }
log_step() { echo -e "${CYAN}→${NC} $*"; }

die() {
    log_error "$*"
    exit 1
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local yn_hint="[Y/n]"
    [[ "$default" == "n" ]] && yn_hint="[y/N]"
    
    echo -en "${BOLD}?${NC} $prompt $yn_hint "
    read -r answer
    answer="${answer:-$default}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local result
    
    if [[ -n "$default" ]]; then
        echo -en "${BOLD}?${NC} $prompt [${DIM}$default${NC}]: "
    else
        echo -en "${BOLD}?${NC} $prompt: "
    fi
    read -r result
    echo "${result:-$default}"
}

detect_shell() {
    local shell_name
    shell_name="$(basename "$SHELL")"
    
    case "$shell_name" in
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                SHELL_RC="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                SHELL_RC="$HOME/.bash_profile"
            fi
            ;;
        zsh)
            SHELL_RC="$HOME/.zshrc"
            ;;
        fish)
            SHELL_RC="$HOME/.config/fish/config.fish"
            ;;
        *)
            SHELL_RC=""
            ;;
    esac
}

#------------------------------------------------------------------------------
# Installation steps
#------------------------------------------------------------------------------

print_banner() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         GitKeeper Installer          ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""
}

check_requirements() {
    log_step "Checking requirements..."
    
    # Check bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        log_warn "Bash 4+ recommended (found: $BASH_VERSION)"
    fi
    
    # Check git
    if ! command -v git &>/dev/null; then
        die "Git is required but not found"
    fi
    
    # Check source files exist
    if [[ ! -f "$GITKEEPER_SOURCE/gitkeeper" ]]; then
        die "GitKeeper source not found at $GITKEEPER_SOURCE"
    fi
    
    log_success "Requirements OK"
}

install_binary() {
    log_step "Installing gitkeeper to $INSTALL_DIR..."
    
    # Create install directory
    mkdir -p "$INSTALL_DIR"
    
    # Copy entire gitkeeper directory structure
    local gitkeeper_home="$HOME/.gitkeeper"
    
    if [[ -d "$gitkeeper_home" ]]; then
        if prompt_yn "GitKeeper already installed at $gitkeeper_home. Overwrite?"; then
            rm -rf "$gitkeeper_home"
        else
            log_warn "Skipping installation"
            return 1
        fi
    fi
    
    # Copy source
    cp -r "$GITKEEPER_SOURCE" "$gitkeeper_home"
    chmod +x "$gitkeeper_home/gitkeeper"
    
    # Create symlink in PATH
    ln -sf "$gitkeeper_home/gitkeeper" "$INSTALL_DIR/gitkeeper"
    
    log_success "Installed to $gitkeeper_home"
    log_success "Symlinked to $INSTALL_DIR/gitkeeper"
}

install_completions() {
    log_step "Installing bash completions..."
    
    # Create completions directory
    mkdir -p "$COMPLETIONS_DIR"
    
    # Copy completion script
    if [[ -f "$GITKEEPER_SOURCE/completions/gitkeeper.bash" ]]; then
        cp "$GITKEEPER_SOURCE/completions/gitkeeper.bash" "$COMPLETIONS_DIR/gitkeeper"
        log_success "Completions installed to $COMPLETIONS_DIR/gitkeeper"
    else
        log_warn "Completion script not found, skipping"
    fi
}

configure_shell() {
    detect_shell
    
    if [[ -z "$SHELL_RC" ]]; then
        log_warn "Could not detect shell config file"
        return 1
    fi
    
    log_step "Configuring shell ($SHELL_RC)..."
    
    local marker="# GitKeeper"
    local path_line="export PATH=\"\$PATH:$INSTALL_DIR\""
    local completion_line="[[ -f \"$COMPLETIONS_DIR/gitkeeper\" ]] && source \"$COMPLETIONS_DIR/gitkeeper\""
    
    # Check if already configured
    if grep -q "$marker" "$SHELL_RC" 2>/dev/null; then
        log_info "Shell already configured"
        return 0
    fi
    
    # Add configuration
    {
        echo ""
        echo "$marker"
        echo "$path_line"
        echo "$completion_line"
    } >> "$SHELL_RC"
    
    log_success "Added to $SHELL_RC"
}

reload_shell_instructions() {
    echo ""
    echo -e "${BOLD}To start using gitkeeper, either:${NC}"
    echo ""
    echo "  1. Restart your terminal"
    echo ""
    echo "  2. Or run:"
    if [[ -n "$SHELL_RC" ]]; then
        echo -e "     ${CYAN}source $SHELL_RC${NC}"
    else
        echo -e "     ${CYAN}export PATH=\"\$PATH:$INSTALL_DIR\"${NC}"
    fi
    echo ""
}

run_config_wizard() {
    if prompt_yn "Run configuration wizard for current repository?" "n"; then
        if [[ -x "$INSTALL_DIR/gitkeeper" ]]; then
            "$INSTALL_DIR/gitkeeper" configure
        elif [[ -x "$GITKEEPER_SOURCE/gitkeeper" ]]; then
            "$GITKEEPER_SOURCE/gitkeeper" configure
        fi
    fi
}

print_success() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Installation Complete! 🎉       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "Quick start:"
    echo -e "  ${CYAN}gitkeeper init${NC}           Create config file"
    echo -e "  ${CYAN}gitkeeper install-hooks${NC}  Set up git hooks"
    echo -e "  ${CYAN}gitkeeper configure${NC}     Interactive setup"
    echo -e "  ${CYAN}gitkeeper check${NC}          Run checks"
    echo ""
}

#------------------------------------------------------------------------------
# Uninstall
#------------------------------------------------------------------------------

do_uninstall() {
    print_banner
    echo -e "${YELLOW}Uninstalling GitKeeper...${NC}"
    echo ""
    
    local gitkeeper_home="$HOME/.gitkeeper"
    
    # Remove symlink
    if [[ -L "$INSTALL_DIR/gitkeeper" ]]; then
        rm "$INSTALL_DIR/gitkeeper"
        log_success "Removed $INSTALL_DIR/gitkeeper"
    fi
    
    # Remove installation directory
    if [[ -d "$gitkeeper_home" ]]; then
        rm -rf "$gitkeeper_home"
        log_success "Removed $gitkeeper_home"
    fi
    
    # Remove completions
    if [[ -f "$COMPLETIONS_DIR/gitkeeper" ]]; then
        rm "$COMPLETIONS_DIR/gitkeeper"
        log_success "Removed completions"
    fi
    
    # Note about shell config
    detect_shell
    if [[ -n "$SHELL_RC" ]] && grep -q "# GitKeeper" "$SHELL_RC" 2>/dev/null; then
        log_warn "Manual cleanup needed in $SHELL_RC"
        echo "  Remove lines between '# GitKeeper' markers"
    fi
    
    echo ""
    log_success "GitKeeper uninstalled"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    # Parse arguments
    case "${1:-}" in
        --uninstall|-u)
            do_uninstall
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --uninstall, -u   Uninstall GitKeeper"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Environment variables:"
            echo "  GITKEEPER_INSTALL_DIR      Installation directory (default: ~/.local/bin)"
            echo "  GITKEEPER_COMPLETIONS_DIR  Completions directory"
            exit 0
            ;;
    esac
    
    print_banner
    
    check_requirements
    echo ""
    
    # Confirm installation
    echo "GitKeeper will be installed to:"
    echo -e "  Binary:      ${CYAN}$INSTALL_DIR/gitkeeper${NC}"
    echo -e "  Home:        ${CYAN}$HOME/.gitkeeper${NC}"
    echo -e "  Completions: ${CYAN}$COMPLETIONS_DIR${NC}"
    echo ""
    
    if ! prompt_yn "Continue with installation?"; then
        echo "Installation cancelled."
        exit 0
    fi
    echo ""
    
    install_binary || exit 1
    install_completions
    configure_shell
    
    print_success
    reload_shell_instructions
    run_config_wizard
}

main "$@"
