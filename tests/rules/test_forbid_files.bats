#!/usr/bin/env bats
#
# forbid_files blocks real env files by name. It also used to block the
# secret-free template every repo is supposed to track: both the built-in
# `\.env\.[a-z]+$` and the shipped `(^|/)\.env\..*` match `.env.example`.
# Measured 2026-09-13, nine repos track one, and the rule rejected a FenrirBot
# branch for a template that had already been reviewed and merged.
#
# The carve-out is deliberately narrow: three exact template names, nothing
# else. These tests pin both halves -- the templates pass, and every real env
# file, near-miss name and template in a forbidden directory is still rejected
# -- plus the reason the carve-out is safe at all: template CONTENT is still
# scanned by the secrets rule.

load '../helpers/rule_repo'

setup() {
    setup_rule_repo
    # shellcheck source=../../rules/forbid_files.sh
    source "$GITKEEPER_ROOT/rules/forbid_files.sh"
    # shellcheck source=../../rules/secrets.sh
    source "$GITKEEPER_ROOT/rules/secrets.sh"
    use_shipped_line pattern_forbid_files
}

teardown() { teardown_gitkeeper; }

#------------------------------------------------------------------------------
# Templates pass
#------------------------------------------------------------------------------

@test "a root .env.example template is not a forbidden file" {
    stage_alone .env.example

    run rule_forbid_files staged

    [ "$status" -eq 0 ]
}

@test "a .env.sample template is not a forbidden file" {
    stage_alone .env.sample

    run rule_forbid_files staged

    [ "$status" -eq 0 ]
}

@test "a .env.template template is not a forbidden file" {
    stage_alone .env.template

    run rule_forbid_files staged

    [ "$status" -eq 0 ]
}

@test "a nested template is not a forbidden file (lycee-app keeps api/ and web/ copies)" {
    stage_alone api/.env.example

    run rule_forbid_files staged

    [ "$status" -eq 0 ]
}

@test "the carve-out lives in the rule, not only in the shipped config" {
    # Repos without a config of their own run on the built-in patterns, and the
    # built-in `\.env\.[a-z]+$` matched the template too.
    use_builtins_only
    stage_alone .env.example

    run rule_forbid_files staged

    [ "$status" -eq 0 ]
}

#------------------------------------------------------------------------------
# Real env files are still rejected
#------------------------------------------------------------------------------

@test "a real .env is still rejected" {
    stage_alone .env

    run rule_forbid_files staged

    [ "$status" -eq 1 ]
    [[ "$output" == *".env"* ]]
}

@test "a .env.local is still rejected" {
    stage_alone .env.local

    run rule_forbid_files staged

    [ "$status" -eq 1 ]
    [[ "$output" == *".env.local"* ]]
}

@test "a .env.production is still rejected" {
    stage_alone .env.production

    run rule_forbid_files staged

    [ "$status" -eq 1 ]
    [[ "$output" == *".env.production"* ]]
}

@test "a nested .env.local is still rejected" {
    stage_alone api/.env.local

    run rule_forbid_files staged

    [ "$status" -eq 1 ]
}

@test "on built-in patterns alone, .env.local is still rejected" {
    use_builtins_only
    stage_alone .env.local

    run rule_forbid_files staged

    [ "$status" -eq 1 ]
}

@test "a name that only resembles a template is still rejected" {
    # The allowlist is exact. `.env.example.local` is the classic way a real
    # env file ends up next to its template; `config.env.example`-style names
    # are not allowlisted because no repo in the estate tracks one.
    local name
    for name in .env.example.local .env.examples .env.example.bak \
                .env.EXAMPLE .env.dist config.env.example; do
        stage_alone "$name"
        run rule_forbid_files staged
        echo "checked: $name -> status $status"
        [ "$status" -eq 1 ]
    done
}

@test "a template inside a forbidden directory is still rejected" {
    # A template is judged by where it lives: only its NAME is allowlisted.
    stage_alone node_modules/some-pkg/.env.example

    run rule_forbid_files staged

    [ "$status" -eq 1 ]
    [[ "$output" == *"node_modules/some-pkg/.env.example"* ]]
}

#------------------------------------------------------------------------------
# Why the carve-out is safe: template content is still scanned
#------------------------------------------------------------------------------

@test "a credential pasted into a template is still caught by secrets" {
    use_shipped_line pattern_secrets
    stage_alone .env.example "GITHUB_PAT=ghp_$(rep a 36)"

    run rule_secrets staged

    [ "$status" -eq 1 ]
}
