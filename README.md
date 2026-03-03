# GitKeeper

Git repository quality gate — catch secrets, forbidden files, and policy violations before they hit your repo.

## Features

- 🔐 **Secret detection** — API keys, tokens, private keys, passwords
- 🚫 **Forbidden files** — Block `.env`, credentials, private keys
- 📝 **Changelog enforcement** — Ensure CHANGELOG updates with code changes
- 🌿 **Branch naming** — Enforce naming conventions
- 📦 **Large file detection** — Prevent repo bloat
- ⚠️ **Merge conflict markers** — Catch leftover `<<<<<<<` markers
- 🎯 **TODO tracking** — Surface new TODO/FIXME comments
- 🧩 **Modular architecture** — Easy to extend and maintain

## Architecture

```
gitkeeper/
├── gitkeeper              # Main entry point (thin dispatcher)
├── .gitkeeper.conf        # Configuration file
│
├── lib/                   # Core modules
│   ├── core.sh           # Logging, colors, utilities
│   ├── config.sh         # Config parsing and access
│   ├── scope.sh          # Scope resolution (files/diff)
│   └── runner.sh         # Rule execution engine
│
├── commands/              # Command implementations
│   ├── check.sh          # gitkeeper check
│   ├── init.sh           # gitkeeper init
│   ├── install-hooks.sh  # gitkeeper install-hooks
│   ├── explain.sh        # gitkeeper explain
│   └── help.sh           # gitkeeper help
│
├── rules/                 # Individual rule modules
│   ├── secrets.sh        # Detect leaked secrets
│   ├── forbid_files.sh   # Block sensitive files
│   ├── changelog.sh      # Require changelog updates
│   ├── version.sh        # Check version files
│   ├── readme.sh         # Verify README exists
│   ├── todos.sh          # Track TODO comments
│   ├── branch_name.sh    # Enforce branch naming
│   ├── large_files.sh    # Prevent large files
│   └── merge_conflict.sh # Detect conflict markers
│
└── .githooks/             # Git hooks
    ├── pre-commit
    └── pre-push
```

## Installation

### Quick Install

```bash
git clone https://github.com/Spifuth/GitKeeper.git
cd gitkeeper
./install.sh
```

The installer will:
- Install GitKeeper to `~/.gitkeeper`
- Add `gitkeeper` to your PATH (`~/.local/bin`)
- Set up bash/zsh completions
- Configure your shell

### Manual Install

```bash
# Clone repository
git clone https://github.com/Spifuth/GitKeeper.git

# Add to PATH (add to your .bashrc/.zshrc)
export PATH="$PATH:/path/to/gitkeeper"

# Source completions
source /path/to/gitkeeper/completions/gitkeeper.bash
```

### Uninstall

```bash
./install.sh --uninstall
```

## Quick Start

```bash
# Initialize in your project
cd your-project
gitkeeper init              # Create config file
gitkeeper configure         # Interactive setup (optional)
gitkeeper install-hooks     # Set up git hooks
```

## Commands

### `gitkeeper check`

Run rules on a scope.

```bash
gitkeeper check                     # Check staged files (default)
gitkeeper check --scope staged      # Pre-commit: staged changes
gitkeeper check --scope push        # Pre-push: commits to be pushed
gitkeeper check --scope pr          # CI: PR/MR diff
gitkeeper check --scope stash       # Audit stash contents
gitkeeper check --scope range:origin/main..HEAD  # Custom range
```

### `gitkeeper init`

Generate a starter `.gitkeeper.conf` file.

```bash
gitkeeper init           # Create config
gitkeeper init --force   # Overwrite existing
```

### `gitkeeper configure`

Interactive menu-based configuration wizard.

```bash
gitkeeper configure      # Configure .gitkeeper.conf interactively
```

Features:
- Toggle rules on/off
- Set behavior options (fail on error/warn)
- Configure custom patterns for each rule
- Saves changes to config file

### `gitkeeper install-hooks`

Install git hooks that run gitkeeper automatically.

```bash
gitkeeper install-hooks                    # Install to .githooks/
gitkeeper install-hooks --hooks-dir hooks  # Custom directory
```

This creates:
- `.githooks/pre-commit` → runs `gitkeeper check --scope staged`
- `.githooks/pre-push` → runs `gitkeeper check --scope push`

And configures `git config core.hooksPath .githooks`

### `gitkeeper explain`

Debug mode — show what will be checked without running.

```bash
gitkeeper explain --scope staged
```

## Configuration

Default path: `.gitkeeper.conf` (override with `--config`)

```ini
# Rules to run (comma-separated)
rules=secrets,forbid_files,merge_conflict,large_files

# When to fail: error|warn
fail_on=error

# Stash checking (optional)
check_stash=0
stash_fail_on=warn

# Rule parameters
pattern_secrets=CUSTOM_[A-Z0-9]{32}
pattern_forbid_files=\.secret$,private/.*
pattern_branch_name=(feature|bugfix|hotfix)/[a-z0-9-]+
pattern_large_files=10485760
trigger_changelog=\.(js|ts|py|go)$
required_version=package.json,VERSION
```

## Available Rules

| Rule | Description | Scope |
|------|-------------|-------|
| `secrets` | Detect API keys, tokens, passwords in diff | all |
| `forbid_files` | Block sensitive file patterns | all |
| `changelog` | Require CHANGELOG update with code changes | push, pr |
| `version` | Check for version file updates | push, pr |
| `readme` | Verify README exists | all |
| `todos` | Warn on new TODO/FIXME comments | all |
| `branch_name` | Enforce branch naming conventions | all |
| `large_files` | Block files over size limit | all |
| `merge_conflict` | Detect leftover conflict markers | all |

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | OK — all checks passed |
| `1` | Warnings (only fails if `fail_on=warn`) |
| `2` | Errors — checks failed |

## CI Integration

### GitHub Actions

```yaml
name: GitKeeper
on: [pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for diff
      
      - name: Run GitKeeper
        env:
          GITKEEPER_PR_BASE: origin/${{ github.base_ref }}
        run: |
          chmod +x ./gitkeeper
          ./gitkeeper check --scope pr
```

### GitLab CI

```yaml
gitkeeper:
  stage: test
  script:
    - chmod +x ./gitkeeper
    - export GITKEEPER_PR_BASE="origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
    - ./gitkeeper check --scope pr
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

## Creating Custom Rules

Add custom rules to the `rules/` directory. Each rule is a self-contained bash script:

```bash
#!/usr/bin/env bash
#
# Rule: no_debug
# Block debug statements from being committed
#

rule_no_debug() {
    local scope="$1"
    set_current_rule "no_debug"
    
    local diff
    diff="$(get_scope_diff "$scope")"
    
    if [[ -z "$diff" ]]; then
        rule_skip "no changes"
        return 3
    fi
    
    # Check for debug statements in added lines
    if echo "$diff" | grep -qE '^\+.*(console\.log|debugger|print\()'; then
        rule_fail "debug statements found"
        return 1
    fi
    
    rule_pass
    return 0
}
```

### Rule API

| Function | Description |
|----------|-------------|
| `set_current_rule "name"` | Set rule name for logging |
| `rule_pass "msg"` | Mark passed (return 0) |
| `rule_warn "msg"` | Mark warning (return 2) |
| `rule_fail "msg"` | Mark failed (return 1) |
| `rule_skip "msg"` | Mark skipped (return 3) |
| `get_scope_files "$scope"` | Get list of files in scope |
| `get_scope_diff "$scope"` | Get diff content |
| `config_get_pattern "rule"` | Get `pattern_<rule>` from config |
| `config_get_trigger "rule"` | Get `trigger_<rule>` from config |
| `log_debug "msg"` | Debug output (when verbose) |

Then enable in config:
```ini
rules=secrets,forbid_files,no_debug
```

## Hook Mapping

| Hook | Command | Trigger |
|------|---------|---------|
| `pre-commit` | `gitkeeper check --scope staged` | Blocks commit |
| `pre-push` | `gitkeeper check --scope push` | Blocks push |
| CI PR check | `gitkeeper check --scope pr` | Required status |

## Uninstall Hooks

```bash
git config --unset core.hooksPath
rm -rf .githooks/
```

## License

MIT