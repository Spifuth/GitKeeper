#!/usr/bin/env bash
#
# Shared bats helper for rule tests: a scratch git repository, the rule
# libraries, and a way to load ONE line of the shipped .gitkeeper.conf.
#
# Rule tests load the patterns from the repository's own .gitkeeper.conf rather
# than restating them: what has to be proven is that the line people actually
# copy into their repos catches what it claims to and nothing else. A copy of
# the pattern in a test would keep passing after the shipped line drifted.

load '../helpers/setup'

setup_rule_repo() {
    setup_gitkeeper
    # shellcheck source=../../lib/scope.sh
    source "$GITKEEPER_ROOT/lib/scope.sh"
    # shellcheck source=../../lib/runner.sh
    source "$GITKEEPER_ROOT/lib/runner.sh"

    # Isolate from the developer's own git config: a global core.hooksPath
    # would run the real GitKeeper hooks on these scratch commits.
    export GIT_CONFIG_GLOBAL="$TEST_TMPDIR/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    git config --global user.name "GitKeeper Test"
    git config --global user.email "test@example.invalid"
    git config --global init.defaultBranch main

    unset GITKEEPER_FILE_FILTER GITKEEPER_PUSH_RANGES

    git init -q "$TEST_TMPDIR/work"
    cd "$TEST_TMPDIR/work" || return 1
    printf 'base\n' > base.txt
    git add base.txt
    git commit -q -m base
}

# Loads only the given key's line from the shipped .gitkeeper.conf, so a test
# exercises that line and the built-in patterns, and nothing else.
use_shipped_line() {
    local key="$1"
    grep -m1 "^${key}=" "$GITKEEPER_ROOT/.gitkeeper.conf" > "$TEST_TMPDIR/test.conf"
    [[ -s "$TEST_TMPDIR/test.conf" ]] || { echo "no ${key}= line in .gitkeeper.conf" >&2; return 1; }
    parse_config "$TEST_TMPDIR/test.conf"
}

# Built-in patterns only: a config file that sets no pattern at all.
use_builtins_only() {
    printf 'rules=secrets,forbid_files\n' > "$TEST_TMPDIR/test.conf"
    parse_config "$TEST_TMPDIR/test.conf"
}

# Stages one file, ALONE: the index is reset first. Planting several files at
# once proves nothing -- one match fails the whole rule while the others are
# never looked at.
stage_alone() {
    local path="$1" content="${2:-PLACEHOLDER=changeme}"
    git reset -q
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    git add -f -- "$path"
}

# Prints $2 copies of the character $1. Credential-shaped test input is built at
# run time with this, so that no line of the test suite is itself a match --
# otherwise GitKeeper's own hooks would reject the commit that adds the test.
rep() {
    local s
    printf -v s '%*s' "$2" ''
    printf '%s' "${s// /$1}"
}
