# Installation

## Quick Install

```bash
git clone https://github.com/Spifuth/GitKeeper.git
cd GitKeeper
./install.sh
```

The installer:
- Copies GitKeeper to `~/.gitkeeper/`
- Adds `gitkeeper` to your PATH via `~/.local/bin`
- Installs bash/zsh completions
- Configures your shell

## Manual Install

```bash
git clone https://github.com/Spifuth/GitKeeper.git
# Add to PATH in your .bashrc/.zshrc
export PATH="$PATH:/path/to/gitkeeper"
```

## Uninstall

```bash
./install.sh --uninstall
```

## Set Up in a Project

```bash
cd your-project
gitkeeper init              # Creates .gitkeeper.conf
gitkeeper configure         # Interactive wizard (optional)
gitkeeper install-hooks     # Installs pre-commit + pre-push hooks
```

## Running Manually

```bash
gitkeeper check                    # Check staged files (default)
gitkeeper check --scope push       # Check commits to be pushed
gitkeeper check --scope pr         # Check PR diff (CI)
```
