#!/usr/bin/env bats
#
# `gitkeeper init` writes the starter config from a heredoc that is a second
# copy of the shipped .gitkeeper.conf. A pattern fixed in one copy and not the
# other ships the old bug to every new repo, so the two are pinned identical.

load '../helpers/setup'

setup() { setup_gitkeeper; }
teardown() { teardown_gitkeeper; }

@test "gitkeeper init writes exactly the shipped .gitkeeper.conf" {
    run "$GITKEEPER_ROOT/gitkeeper" init -o "$TEST_TMPDIR/generated.conf"
    [ "$status" -eq 0 ]

    run diff "$TEST_TMPDIR/generated.conf" "$GITKEEPER_ROOT/.gitkeeper.conf"
    echo "$output"
    [ "$status" -eq 0 ]
}
