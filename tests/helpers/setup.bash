#!/usr/bin/env bash
#
# Shared bats helper: locate the repo, source the libraries under test, and
# give each test its own scratch directory.
#
# Deliberately sources lib/ directly rather than driving the `gitkeeper`
# entry point. These are unit tests of the config parser; going through the
# CLI would make a parser bug look like a rule bug.

setup_gitkeeper() {
    GITKEEPER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    export GITKEEPER_ROOT

    # core.sh first: config.sh calls log_debug() and die() from it.
    # shellcheck source=../../lib/core.sh
    source "$GITKEEPER_ROOT/lib/core.sh"
    # shellcheck source=../../lib/config.sh
    source "$GITKEEPER_ROOT/lib/config.sh"

    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
}

teardown_gitkeeper() {
    [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
    return 0
}

# Writes $2 as the body of a config file named $1 inside the scratch dir and
# echoes its path.
write_config() {
    local name="$1" body="$2"
    printf '%s\n' "$body" > "$TEST_TMPDIR/$name"
    echo "$TEST_TMPDIR/$name"
}
