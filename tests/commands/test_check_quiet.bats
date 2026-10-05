#!/usr/bin/env bats
#
# `gitkeeper check -q` was documented as "Minimal output" but only exported a
# variable nothing read. Quiet now means: a clean run prints nothing, a dirty
# run prints only the rule lines that warned or failed (with their details)
# plus the verdict -- and the exit code is exactly what it is without -q.

load '../helpers/rule_repo'

setup() {
    setup_rule_repo
    unset GITKEEPER_QUIET GITKEEPER_VERBOSE
    printf 'rules=forbid_files,merge_conflict\nfail_on=error\n' > .gitkeeper.conf
    git add .gitkeeper.conf
    git commit -q -m config
}
teardown() { teardown_gitkeeper; }

@test "check -q on a clean staged change prints nothing and exits 0" {
    stage_alone notes.txt "harmless"

    run "$GITKEEPER_ROOT/gitkeeper" check -q
    echo "$output"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "check without -q still prints the full report" {
    stage_alone notes.txt "harmless"

    run "$GITKEEPER_ROOT/gitkeeper" check
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitKeeper Check"* ]]
    [[ "$output" == *"✓ forbid_files"* ]]
    [[ "$output" == *"All checks passed"* ]]
}

@test "check -q on a failing change prints the failure and its details, and exits 2" {
    stage_alone .env "harmless"

    run "$GITKEEPER_ROOT/gitkeeper" check --quiet
    echo "$output"
    [ "$status" -eq 2 ]
    [[ "$output" == *"✗ forbid_files"* ]]
    [[ "$output" == *".env"* ]]
    [[ "$output" == *"Check failed"* ]]
    # Nothing that passed, no banner, no info lines.
    [[ "$output" != *"✓"* ]]
    [[ "$output" != *"GitKeeper Check"* ]]
    [[ "$output" != *"Scope:"* ]]
}

@test "check -q exits with the same code as check without it" {
    stage_alone .env "harmless"

    run "$GITKEEPER_ROOT/gitkeeper" check
    local loud=$status
    run "$GITKEEPER_ROOT/gitkeeper" check -q
    [ "$status" -eq "$loud" ]
}
