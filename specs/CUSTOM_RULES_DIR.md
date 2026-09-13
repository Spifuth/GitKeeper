# Spec: custom rules directory

## Goal
Let teams drop project-local rules into a directory without forking
GitKeeper or modifying the install. Rules in the custom dir are loaded
alongside built-in rules transparently.

## Activation
  export GITKEEPER_CUSTOM_RULES_DIR=/path/to/your/rules

Or in the shell profile / CI environment. The config file has no setting
for this — it must be an env var because the path is host-specific,
not repo-specific.

## Files to modify

### lib/runner.sh

#### list_available_rules()
Currently only scans GITKEEPER_RULES_DIR. Add:

  list_available_rules() {
      # Built-in rules
      for rule_file in "$GITKEEPER_RULES_DIR"/*.sh; do
          [[ -f "$rule_file" ]] && basename "$rule_file" .sh
      done

      # Custom rules (if dir is set and exists)
      if [[ -n "${GITKEEPER_CUSTOM_RULES_DIR:-}" && \
            -d "$GITKEEPER_CUSTOM_RULES_DIR" ]]; then
          for rule_file in "$GITKEEPER_CUSTOM_RULES_DIR"/*.sh; do
              [[ -f "$rule_file" ]] && basename "$rule_file" .sh
          done
      fi
  }

#### rule_exists()
  rule_exists() {
      local rule="$1"
      [[ -f "$GITKEEPER_RULES_DIR/${rule}.sh" ]] && return 0
      if [[ -n "${GITKEEPER_CUSTOM_RULES_DIR:-}" ]]; then
          [[ -f "$GITKEEPER_CUSTOM_RULES_DIR/${rule}.sh" ]] && return 0
      fi
      return 1
  }

#### load_rule()
  load_rule() {
      local rule="$1"

      # Try built-in first
      local rule_file="$GITKEEPER_RULES_DIR/${rule}.sh"

      # Fall back to custom dir
      if [[ ! -f "$rule_file" && -n "${GITKEEPER_CUSTOM_RULES_DIR:-}" ]]; then
          rule_file="$GITKEEPER_CUSTOM_RULES_DIR/${rule}.sh"
      fi

      if [[ ! -f "$rule_file" ]]; then
          log_warn "rule not found: $rule"
          return 1
      fi

      source "$rule_file"
  }

## Collision handling
If a custom rule has the same name as a built-in:
  - Custom dir wins (team override intent).
  - Emit a log_debug notice: "custom rule overrides built-in: $rule"
  - Do NOT emit a warning — this is a valid use case.

## commands/explain.sh
Update the "Available Rules" section to label custom rules:
  ✓ my_rule (enabled, custom)
  ○ another_custom (custom)

## README update required
Add a section: "Custom rules" explaining:
  1. Create a file: rules/no_debug.sh with rule_<name>() function
  2. export GITKEEPER_CUSTOM_RULES_DIR="$(pwd)/rules"
  3. Add rule name to .gitkeeper.conf rules= list
  4. Run gitkeeper explain to verify it's detected

## Security note
Custom rule files are sourced (executed) by gitkeeper. Document that
GITKEEPER_CUSTOM_RULES_DIR should only point to trusted directories.
Do NOT auto-discover rules from .gitkeeper.conf paths.
