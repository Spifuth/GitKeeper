# Rules

GitKeeper ships with 9 built-in rules. Enable/disable them in `.gitkeeper.conf`.

## Available Rules

| Rule | Default | Description |
|------|---------|-------------|
| `secrets` | ✅ | Detect API keys, tokens, passwords in diffs |
| `forbid_files` | ✅ | Block `.env`, credentials, private key files |
| `merge_conflict` | ✅ | Catch leftover `<<<<<<<` markers |
| `large_files` | ✅ | Block files over size limit |
| `changelog` | ❌ | Require CHANGELOG update with code changes |
| `version` | ❌ | Check version file is updated |
| `readme` | ❌ | Verify README exists |
| `todos` | ❌ | Warn on new TODO/FIXME comments |
| `branch_name` | ❌ | Enforce branch naming conventions |

## Configuration

Edit `.gitkeeper.conf` in your project root:

```ini
# Rules to run (comma-separated)
rules=secrets,forbid_files,merge_conflict,large_files

# Fail on: error (only errors) | warn (errors + warnings)
fail_on=error

# Custom patterns
pattern_secrets=CUSTOM_[A-Z0-9]{32}
pattern_forbid_files=\.secret$,private/.*
pattern_branch_name=(feature|bugfix|hotfix)/[a-z0-9-]+
pattern_large_files=10485760
```

## Scopes

| Scope | Trigger | Checks |
|-------|---------|--------|
| `staged` | pre-commit | Staged files only |
| `push` | pre-push | Commits being pushed |
| `pr` | CI | PR diff vs base branch |
| `stash` | manual | Stash contents |
| `range:A..B` | manual | Custom commit range |

## Custom Rules

Add a file to `rules/` in your GitKeeper installation:

```bash
#!/usr/bin/env bash
rule_no_debug() {
    set_current_rule "no_debug"
    local diff; diff="$(get_scope_diff "$1")"
    if echo "$diff" | grep -qE '^\+.*(console\.log|debugger)'; then
        rule_fail "debug statements found"
        return 1
    fi
    rule_pass
}
```

Then add `no_debug` to your `rules=` list.
