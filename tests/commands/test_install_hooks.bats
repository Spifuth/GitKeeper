#!/usr/bin/env bats
#
# `install-hooks --link` used to be accepted and silently ignored. It is now
# refused, on purpose: git skips a dangling hook symlink without a word, so a
# symlinked hook whose target moved (or a committed .githooks/ cloned on
# another machine) would turn the gate off silently. The generated wrappers
# fail loudly instead -- these tests pin both halves of that.

load '../helpers/rule_repo'

setup() { setup_rule_repo; }
teardown() { teardown_gitkeeper; }

@test "install-hooks writes executable wrapper files, not symlinks" {
    run "$GITKEEPER_ROOT/gitkeeper" install-hooks
    echo "$output"
    [ "$status" -eq 0 ]

    for hook in pre-commit pre-push; do
        [ -f ".githooks/$hook" ]
        [ ! -L ".githooks/$hook" ]
        [ -x ".githooks/$hook" ]
    done
    [ "$(git config core.hooksPath)" = ".githooks" ]
}

@test "install-hooks --link is refused and installs nothing" {
    run "$GITKEEPER_ROOT/gitkeeper" install-hooks --link
    echo "$output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--link is not supported"* ]]
    [ ! -e .githooks ]
    run git config core.hooksPath
    [ "$status" -ne 0 ]
}

@test "the generated pre-commit hook fails loudly when gitkeeper is missing" {
    GITKEEPER_BIN=/nonexistent/gitkeeper run "$GITKEEPER_ROOT/gitkeeper" install-hooks
    [ "$status" -eq 0 ]

    PATH=/usr/bin:/bin run .githooks/pre-commit
    echo "$output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"gitkeeper not found"* ]]
}
