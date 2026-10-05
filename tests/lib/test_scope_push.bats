#!/usr/bin/env bats
#
# The push scope decides what a pre-push hook scans. It used to resolve to
# `<upstream>..HEAD`, falling back to a hardcoded `origin/main` — so the first
# push of any new branch re-scanned everything `dev` carries ahead of `main`,
# and one false positive anywhere on `dev` rejected every branch in the repo.
# It also listed files *deleted* by the pushed commits, so `forbid_files`
# rejected a branch for removing a forbidden file.
#
# Git hands the pre-push hook the exact refs being pushed on stdin. These tests
# pin that the scope is those refs and nothing else.

load '../helpers/setup'

setup() {
    setup_gitkeeper
    # shellcheck source=../../lib/scope.sh
    source "$GITKEEPER_ROOT/lib/scope.sh"

    # Isolate from the developer's own git config: a global core.hooksPath
    # would run the real GitKeeper hooks on these scratch commits.
    export GIT_CONFIG_GLOBAL="$TEST_TMPDIR/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    git config --global user.name "GitKeeper Test"
    git config --global user.email "test@example.invalid"
    git config --global init.defaultBranch main
    git config --global advice.detachedHead false

    unset GITKEEPER_PUSH_RANGES

    # A bare remote holding `main`, and `dev` one commit ahead of it. That
    # dev-only commit carries a forbidden file, exactly like the false
    # positive that blocked every push in the nebula repo.
    git init -q --bare "$TEST_TMPDIR/remote.git"
    git init -q "$TEST_TMPDIR/work"
    cd "$TEST_TMPDIR/work"
    git remote add origin "$TEST_TMPDIR/remote.git"
    commit_file base.txt "base"
    git push -q origin main
    git switch -q -c dev
    commit_file deploy.env "PLACEHOLDER=1"
    git push -q origin dev
    git fetch -q origin
}

teardown() { teardown_gitkeeper; }

commit_file() {
    printf '%s\n' "$2" > "$1"
    git add "$1"
    git commit -q -m "add $1"
}

ZERO=0000000000000000000000000000000000000000

#------------------------------------------------------------------------------
# Without hook input: the fallback when there is no upstream
#------------------------------------------------------------------------------

@test "a new branch with no upstream scans only the commits no remote has" {
    git switch -q -c feat/x --no-track origin/dev
    commit_file feature.txt "work"

    run get_scope_files push

    [ "$status" -eq 0 ]
    [ "$output" = "feature.txt" ]
}

@test "files deleted by the pushed commits are not in scope" {
    git switch -q -c feat/cleanup --no-track origin/dev
    git branch -q --set-upstream-to=origin/dev
    git rm -q deploy.env
    commit_file kept.txt "kept"

    run get_scope_files push

    [ "$status" -eq 0 ]
    [ "$output" = "kept.txt" ]
}

#------------------------------------------------------------------------------
# With hook input: the refs git says it is pushing
#------------------------------------------------------------------------------

@test "an existing remote branch resolves to remote_sha..local_sha" {
    git switch -q dev
    local before after
    before="$(git rev-parse HEAD)"
    commit_file more.txt "more"
    after="$(git rev-parse HEAD)"

    run resolve_push_ranges <<< "refs/heads/dev $after refs/heads/dev $before"

    [ "$status" -eq 0 ]
    [ "$output" = "${before}..${after}" ]
}

@test "a new branch on the hook's stdin resolves to the commits the remote lacks" {
    git switch -q -c feat/y --no-track origin/dev
    commit_file feature.txt "work"
    local tip
    tip="$(git rev-parse HEAD)"

    run resolve_push_ranges <<< "refs/heads/feat/y $tip refs/heads/feat/y $ZERO"

    [ "$status" -eq 0 ]
    [ "$output" = "$(git rev-parse origin/dev)..${tip}" ]
}

@test "a branch deletion on the hook's stdin yields no range" {
    run resolve_push_ranges <<< "(delete) $ZERO refs/heads/old $(git rev-parse origin/dev)"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a new branch with nothing the remote lacks yields no range" {
    git switch -q -c feat/empty --no-track origin/dev

    run resolve_push_ranges <<< "refs/heads/feat/empty $(git rev-parse HEAD) refs/heads/feat/empty $ZERO"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "GITKEEPER_PUSH_RANGES wins over a misleading upstream" {
    # An upstream of origin/main is the shape that used to re-scan all of dev.
    git switch -q -c feat/z --no-track origin/dev
    git branch -q --set-upstream-to=origin/main
    commit_file feature.txt "work"
    export GITKEEPER_PUSH_RANGES="$(git rev-parse origin/dev)..$(git rev-parse HEAD)"

    run get_scope_files push

    [ "$status" -eq 0 ]
    [ "$output" = "feature.txt" ]
}

#------------------------------------------------------------------------------
# End to end: what the pre-push hook actually runs
#------------------------------------------------------------------------------

write_repo_config() {
    printf '%s\n' "rules=forbid_files" "fail_on=error" > .gitkeeper.conf
    git add .gitkeeper.conf
    git commit -q -m "gitkeeper config"
}

@test "pre-push does not reject a branch for a forbidden file only dev carries" {
    git switch -q -c feat/clean --no-track origin/dev
    write_repo_config
    commit_file feature.txt "work"

    run "$GITKEEPER_ROOT/gitkeeper" check --scope push \
        <<< "refs/heads/feat/clean $(git rev-parse HEAD) refs/heads/feat/clean $ZERO"

    [ "$status" -eq 0 ]
}

@test "pre-push still rejects a forbidden file in the commits being pushed" {
    git switch -q -c feat/leak --no-track origin/dev
    write_repo_config
    commit_file leaked.env "TOKEN=x"

    run "$GITKEEPER_ROOT/gitkeeper" check --scope push \
        <<< "refs/heads/feat/leak $(git rev-parse HEAD) refs/heads/feat/leak $ZERO"

    [ "$status" -ne 0 ]
    [[ "$output" == *"leaked.env"* ]]
}
