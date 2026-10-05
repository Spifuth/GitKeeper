#!/usr/bin/env bats
#
# The custom secret patterns in the shipped .gitkeeper.conf, verified the way
# that file demands: ONE credential planted ALONE per type, confirmed CAUGHT,
# then benign strings confirmed NOT to fire.
#
# The Infisical pattern used to be `st\.[A-Za-z0-9._-]{20}`: the literal `st.`
# and twenty word characters. Ordinary text has that shape -- on 2026-09-13 it
# rejected a push for `-o merge_request.remove_source_branch` in a plan
# document, and it did it twice more after. A gate that cries wolf on prose is
# a gate people learn to bypass.
#
# Every credential below is assembled at run time with rep(), so that no line
# of this file is itself a match for the patterns it tests.

load '../helpers/rule_repo'

setup() {
    setup_rule_repo
    # shellcheck source=../../rules/secrets.sh
    source "$GITKEEPER_ROOT/rules/secrets.sh"
    use_shipped_line pattern_secrets
}

teardown() { teardown_gitkeeper; }

# Plants $1 as the only added line and expects the rule to fail on it.
assert_caught() {
    stage_alone planted.txt "$1"
    run rule_secrets staged
    echo "planted: $1 -> status $status"
    [ "$status" -eq 1 ]
}

# Plants $1 as the only added line and expects a clean pass.
assert_not_caught() {
    stage_alone planted.txt "$1"
    run rule_secrets staged
    echo "planted: $1 -> status $status"
    echo "$output"
    [ "$status" -eq 0 ]
}

#------------------------------------------------------------------------------
# Infisical service tokens
#------------------------------------------------------------------------------
#
# Format, read from the live Infisical (v0.162.19) source: the server mints
# `st.<token id>.<secret>` with the secret = randomBytes(16) as hex (32 chars),
# and the token handed to a user carries a fourth segment, the 32-hex-char
# client key. The id is a UUID (36 chars) today, a 24-char ObjectId on older
# instances.

@test "an Infisical service token as handed to a user is caught" {
    local id="$(rep a 8)-$(rep b 4)-$(rep c 4)-$(rep d 4)-$(rep e 12)"
    assert_caught "INFISICAL_TOKEN=st.${id}.$(rep 1 32).$(rep 2 32)"
}

@test "the server-side three-segment form of the token is caught" {
    local id="$(rep a 8)-$(rep b 4)-$(rep c 4)-$(rep d 4)-$(rep e 12)"
    assert_caught "st.${id}.$(rep f 32)"
}

@test "a token with a legacy 24-character ObjectId is caught" {
    assert_caught "st.$(rep 6 24).$(rep 0 32).$(rep 9 32)"
}

@test "the glab line that blocked three pushes does not fire" {
    assert_not_caught "+  -o merge_request.remove_source_branch"
}

@test "a dotted attribute chain in code does not fire" {
    # Two dots and long segments: the looser two-dot shape first proposed for
    # this pattern would still have matched it.
    assert_not_caught "perms = request.authentication_backend.get_user_permissions_for(user)"
}

@test "the parser-bug false positive stays fixed" {
    assert_not_caught "const runwaySecondsRemaining = 1"
}

#------------------------------------------------------------------------------
# Every other credential type, re-verified individually
#------------------------------------------------------------------------------
#
# Editing one entry of a comma-separated pattern list can break its neighbours
# (a stray comma or quote silently drops the rest), so the whole line is
# re-checked, one type at a time.

@test "a private key block is caught" {
    assert_caught "BEGIN OPENSSH PRIVATE"" KEY-----"
}

@test "an AWS secret access key is caught" {
    assert_caught "aws_secret_access_key = $(rep A 40)"
}

@test "a JWT is caught" {
    assert_caught "Authorization: Bearer eyJ$(rep a 12).eyJ$(rep b 12).$(rep c 20)"
}

@test "a Discord bot token is caught" {
    assert_caught "DISCORD=M$(rep a 23).$(rep b 6).$(rep c 27)"
}

@test "a Slack webhook URL is caught" {
    assert_caught "https://hooks.slack.com/services/T$(rep A 8)/B$(rep B 8)/$(rep c 24)"
}

@test "an Anthropic API key is caught" {
    assert_caught "sk-ant-$(rep a 24)"
}

@test "an OpenAI project key is caught" {
    assert_caught "sk-proj-$(rep a 20)"
}

@test "a Google API key is caught" {
    assert_caught "AIza$(rep a 35)"
}

@test "a SendGrid key is caught" {
    assert_caught "SG.$(rep a 22).$(rep b 43)"
}

@test "a Telegram bot token is caught" {
    assert_caught "123456789:AA$(rep a 33)"
}

@test "an npm _authToken is caught" {
    assert_caught "//registry.npmjs.org/:_authToken=$(rep a 20)"
}
