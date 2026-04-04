# Spec: lint_errors rule

## File to create
  rules/lint_errors.sh  — function rule_lint_errors()

## Behaviour
Run the appropriate linter for each file extension found in scope.
Fail if any linter exits non-zero. Warn (not fail) if a linter binary
is missing — never block a commit because a tool isn't installed.

## Extension — linter map (built-in defaults)
  .sh .bash          — shellcheck --severity=error
  .js .mjs .cjs      — eslint --no-eslintrc -c {} (or npx eslint if local config exists)
  .ts .tsx           — eslint or tsc --noEmit
  .py                — flake8 --select=E9,F63,F7,F82 (syntax/fatal only)
  .rb                — rubocop --only Lint (if installed)
  .go                — go vet ./...  (run once per module root, not per file)

## Config keys
  lint_errors_tools=shellcheck,eslint,flake8
    Comma list of linters to enable. Default: all.
    Allows disabling e.g. eslint if team doesn't use it.

  lint_errors_fail_on_missing=0
    Default 0 = warn if tool not found, skip gracefully.
    Set 1 to fail if a configured tool is missing.

  lint_errors_args_shellcheck=--severity=warning
    Override default args for a specific linter.
    Pattern: lint_errors_args_<toolname>=<args>

## Algorithm
  1. get_scope_files scope — file list
  2. Group files by extension
  3. For each enabled linter whose extension group is non-empty:
     a. Check tool exists (command -v). If not: warn or skip per config.
     b. Run linter on the file group.
     c. Capture stdout+stderr.
     d. If exit != 0: accumulate failures.
  4. After all linters: rule_fail if any failed, else rule_pass.
  5. Show first 5 lines of linter output per failing tool.

## Output format
  ✗ lint_errors — shellcheck (2 files), flake8 (1 file)
        [shellcheck] app.sh:14:3: error: ...
        [flake8] main.py:8:1: E901 SyntaxError ...

## Important: scope awareness
  Only lint files that are in scope. Do NOT lint the entire repo.
  Use get_scope_files, not git ls-files.

## Go special case
  go vet takes a package path, not a file list.
  When .go files are in scope, find their module root (go.mod location)
  and run `go vet ./...` from there once.

## Do NOT implement
  - Auto-fix (separate --fix spec)
  - Slow linters (eslint full project scan, mypy, etc.)
  - Linters that require network access
