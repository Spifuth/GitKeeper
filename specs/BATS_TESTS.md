# Spec: BATS test suite

## Goal
A test suite using bats-core that covers every rule and key library
function. Must run with `bats tests/` from the repo root. No network,
no real git remotes needed.

## Install requirement
bats-core >= 1.9. Add to README:
  git clone https://github.com/bats-core/bats-core ~/.bats
  export PATH="$HOME/.bats/bin:$PATH"

## Directory layout to create
  tests/
    helpers/
      setup.bash      # shared: create temp git repo, load gitkeeper libs
    rules/
      test_secrets.bats
      test_forbid_files.bats
      test_merge_conflict.bats
      test_large_files.bats
      test_todos.bats
      test_no_debug.bats
      test_changelog.bats
      test_branch_name.bats
      test_readme.bats
      test_version.bats
    lib/
      test_config.bats
      test_scope.bats

## helpers/setup.bash must do
  - Create a temp dir with `mktemp -d`
  - Run `git init` in it
  - `git config user.email` and `user.name` so commits work
  - Source all gitkeeper libs (core, config, scope, runner)
  - Source all rule files
  - Export GITKEEPER_ROOT pointing at repo root
  - Provide helper: `stage_file <name> <content>` — writes + stages a file
  - Provide helper: `stage_patch <content>` — applies a raw diff to index
  - Teardown: `rm -rf "$BATS_TMPDIR"`

## Pattern for each rule test file
  @test "secrets: passes when no secrets in diff" {
    stage_file "app.js" 'const x = 1'
    run rule_secrets staged
    [ "$status" -eq 0 ]
  }

  @test "secrets: fails on AWS key" {
    stage_file "app.js" 'const key = "FAKEKEYDONOTUSE12345"'
    run rule_secrets staged
    [ "$status" -eq 1 ]
  }

  @test "secrets: skips when diff is empty" {
    run rule_secrets staged   # nothing staged
    [ "$status" -eq 3 ]
  }

## Coverage required per rule (minimum)
  - pass case (clean input)
  - fail case (each category of violation)
  - skip case (empty scope / wrong scope)
  - custom pattern via GITKEEPER_CONFIG override

## Config lib tests must cover
  - parse_config: key=value, comments, blank lines
  - parse_config: value containing = (regex patterns)
  - find_config: finds config searching upward
  - apply_config_overlay: only overrides stated keys
  - config_fail_on_warn: true/false

## Scope lib tests must cover
  - get_scope_files staged: returns staged files only
  - GITKEEPER_FILE_FILTER: filters correctly
  - get_scope_diff: diff contains only + lines for new content

## CI integration
Add to GitHub Actions workflow:
  - name: Run tests
    run: |
      bats tests/
