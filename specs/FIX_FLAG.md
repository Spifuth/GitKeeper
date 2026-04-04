# Spec: --fix flag

## Goal
gitkeeper check --fix attempts to auto-remediate safe, mechanical
violations instead of just reporting them. Only deterministic fixes
are applied — nothing that requires judgment.

## Invocation
  gitkeeper check --fix
  gitkeeper check --scope staged --fix

## Fixable violations (whitelist — be conservative)
  Rule            What gets fixed
  ──────────────────────────────────────────────────────────────
  todos           Nothing. Todos need human decisions.
  merge_conflict  Nothing. Conflict resolution needs human input.
  large_files     Nothing. Can't auto-shrink binary files.
  secrets         Nothing. Can't safely redact secrets automatically.
  forbid_files    Nothing. Deleting committed files is destructive.
  no_debug        FIXABLE: remove the offending line(s) from the file.
  file_encoding   FIXABLE: convert CRLF → LF with sed -i.
  branch_name     Nothing. Can't rename branches non-interactively.

## Files to modify

### commands/check.sh
Add --fix to argument parsing:
  -f|--fix)  export GITKEEPER_FIX_MODE=1; shift ;;

After run_all_rules, if GITKEEPER_FIX_MODE=1 and there were failures:
  if [[ "$GITKEEPER_FIX_MODE" -eq 1 && $grand_failed -gt 0 ]]; then
      echo ""
      log_info "Attempting auto-fix..."
      run_all_rules_fix "$scope"
  fi

### lib/runner.sh
Add run_all_rules_fix():

  run_all_rules_fix() {
      local scope="$1"
      local rules_string
      rules_string="$(config_get_rules)"
      IFS=',' read -ra rules <<< "$rules_string"

      local fixed=0
      for rule in "${rules[@]}"; do
          rule="$(trim "$rule")"
          [[ -z "$rule" ]] && continue

          # Only call fix function if it exists for this rule
          if declare -f "rule_fix_${rule}" &>/dev/null; then
              rule_fix_"${rule}" "$scope" && (( fixed++ )) || true
          fi
      done

      if [[ $fixed -gt 0 ]]; then
          log_success "$fixed rule(s) auto-fixed"
          log_info "Review changes with: git diff"
          log_info "Re-stage with: git add -p"
      else
          log_info "No auto-fixes available for these violations"
      fi
  }

### rules/no_debug.sh — add rule_fix_no_debug()
This is the only rule with a fix function in the initial implementation.

  rule_fix_no_debug() {
      local scope="$1"

      # Only fix staged files — don't touch unstaged working tree
      [[ "$scope" != "staged" ]] && return 1

      local files
      files="$(get_scope_files "$scope")"
      [[ -z "$files" ]] && return 1

      local fixed_count=0

      while IFS= read -r file; do
          [[ -z "$file" || ! -f "$file" ]] && continue

          # Get lines to remove from the diff (lines that triggered no_debug)
          local diff
          diff="$(git diff --cached -- "$file")"

          local bad_lines=()
          # Re-run the same patterns from rule_no_debug to find offending lines
          # ... (re-use pattern array, collect line numbers from diff hunk headers)

          # For each bad line number: remove it from the file
          # Use sed -i to delete those lines
          # Then re-stage: git add "$file"

          (( fixed_count++ )) || true
      done <<< "$files"

      return $(( fixed_count > 0 ? 0 : 1 ))
  }

Implementation note: extracting line numbers from unified diff hunk headers
(@@ -a,b +c,d @@) is the key challenge. Parse the +c offset and add the
position of each matched line within the hunk.

## Safety rules — non-negotiable
1. NEVER fix push or pr scope. Only staged.
2. NEVER git add automatically. Print the command; let the user run it.
   Exception: if --fix is combined with --auto-stage (a separate future flag).
3. Always print what was changed before changing it.
4. If fix fails, leave the file unchanged and report the error.
5. Create a backup: cp "$file" "${file}.gitkeeper.bak" before editing.
   Clean up bak files if fix succeeds.

## Output format
  ✓ Fixing no_debug in src/api/routes.js...
    Removed line 42: console.log(req.body)
    Removed line 87: debugger;
  ✓ Fixed 2 line(s). Review with: git diff src/api/routes.js

## help.sh update
Add to --fix documentation:
  Only removes debug statements automatically.
  All other violations require manual intervention.
  Always review with git diff before committing.
