# Spec: inline ignores

## Purpose
Let developers suppress a specific rule finding on a specific line by
adding a comment. Without this, a single false positive forces disabling
the whole rule in config — which is too blunt.

## Syntax
  <code>  # gitkeeper-ignore
  <code>  # gitkeeper-ignore: secrets
  <code>  # gitkeeper-ignore: secrets,forbid_files

No ignore — rule fires normally.
Bare ignore — suppresses ALL rules for that line.
With rule list — suppresses only named rules.

## Files to modify

### lib/core.sh
Add one new function:

  # Check if an added diff line carries a gitkeeper-ignore comment.
  # Args: $1 = raw diff line (including leading +)
  #       $2 = rule name to check (optional; if empty, any ignore matches)
  # Returns 0 if the line should be suppressed for this rule, 1 otherwise.
  line_is_ignored() {
      local line="$1"
      local rule="${2:-}"

      # Match: # gitkeeper-ignore or # gitkeeper-ignore: rule1,rule2
      if [[ "$line" =~ \#[[:space:]]*gitkeeper-ignore([[:space:]]*:[[:space:]]*([a-z_,[:space:]]+))? ]]; then
          local rule_list="${BASH_REMATCH[2]}"
          # Bare ignore (no rule list) — suppress everything
          [[ -z "$rule_list" ]] && return 0
          # Check if our rule is in the list
          local r
          IFS=',' read -ra rs <<< "$rule_list"
          for r in "${rs[@]}"; do
              r="$(trim "$r")"
              [[ "$r" == "$rule" ]] && return 0
          done
      fi
      return 1
  }

### rules/*.sh — all rules that grep added lines
Every rule that does:
  grep -Ei "$pattern" <<< "$diff"
needs to pipe through a filter first.

Provide a helper in lib/core.sh:

  # Filter added lines from a diff, removing lines that carry a
  # gitkeeper-ignore comment for the given rule.
  # Usage: echo "$diff" | filter_ignored_lines "secrets"
  filter_ignored_lines() {
      local rule="${1:-}"
      while IFS= read -r line; do
          line_is_ignored "$line" "$rule" || echo "$line"
      done
  }

Then in each rule, replace:
  echo "$diff" | grep -E '^\+' | grep -v '^+++' | grep -Ei "$pattern"
with:
  echo "$diff" | grep -E '^\+' | grep -v '^+++' \
      | filter_ignored_lines "$CURRENT_RULE" \
      | grep -Ei "$pattern"

### Rules that need updating
  rules/secrets.sh         — main pattern grep loop
  rules/no_debug.sh        — added_lines collection loop
  rules/todos.sh           — new_todos grep
  rules/merge_conflict.sh  — found check greps
  rules/forbid_files.sh    — does file-level not line-level; skip (see below)

### forbid_files.sh special case
forbid_files checks filenames, not line content. The ignore comment
can't live on a diff line. Instead, support a file-level directive:
if the file's first line (in the diff) contains # gitkeeper-ignore: forbid_files
treat the whole file as ignored for that rule.

## Output: tell the user when a line was suppressed
In --verbose mode, log_debug each suppressed line:
  » secrets: suppressed 1 line(s) via inline ignore

## Do NOT do
- Ignore entire files via inline comment (use .gitkeeper.ignore for that)
- Support /* gitkeeper-ignore */ block comments — too complex to parse reliably
- Strip the ignore comment from displayed output — show it so user knows why

## Config: allow disabling inline ignores entirely
  allow_inline_ignore=1   (default 1 = enabled)
  Set 0 to prevent developers from suppressing rule findings inline.
  Useful for security-critical repos.
