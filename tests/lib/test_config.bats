#!/usr/bin/env bats
#
# The config parser is the most load-bearing code in GitKeeper: every rule
# compiles its patterns from a value this file produced. A parser that alters
# a value does not fail — it enforces a rule nobody wrote, in both directions
# at once (a pattern that matches too much, and one that matches nothing).
#
# So these tests assert byte-identity, not "looks about right".

load '../helpers/setup'

setup() { setup_gitkeeper; }
teardown() { teardown_gitkeeper; }

#------------------------------------------------------------------------------
# The regression these tests were written for
#------------------------------------------------------------------------------

@test "a secret pattern survives parsing byte for byte" {
    # Every character here is load-bearing:
    #   ['\"]?  the single quote is an alternative in the class, and the
    #           backslash escapes the double quote
    #   \s      whitespace, not the letter s
    #   \.      a literal dot, not "any character"
    local pattern="aws_secret_access_key['\\\"]?\\s*[=:]\\s*['\\\"]?[A-Za-z0-9/+=]{40}"
    local file
    file="$(write_config ".gitkeeper.conf" "pattern_secrets=$pattern")"

    parse_config "$file"

    [ "${GITKEEPER_CONFIG[pattern_secrets]}" = "$pattern" ]
}

@test "backslash escapes are not eaten: st\\. stays an escaped dot" {
    # Unescaped, `st.` matches any character after "st" — which is how a line
    # reading `const runwaySecondsRemaining = 1` gets reported as a secret.
    local file
    file="$(write_config ".gitkeeper.conf" 'pattern_secrets=st\.[A-Za-z0-9._-]{20}')"

    parse_config "$file"

    [ "${GITKEEPER_CONFIG[pattern_secrets]}" = 'st\.[A-Za-z0-9._-]{20}' ]
}

@test "\\s stays whitespace and does not decay into the letter s" {
    # `_authTokens*=s*` matches "_authToken" followed by literal s's. The
    # ordinary `_authToken = value` form stops being detected entirely.
    local file
    file="$(write_config ".gitkeeper.conf" 'pattern_secrets=_authToken\s*=\s*[A-Za-z0-9_-]{20}')"

    parse_config "$file"

    [ "${GITKEEPER_CONFIG[pattern_secrets]}" = '_authToken\s*=\s*[A-Za-z0-9_-]{20}' ]
}

@test "the shipped default pattern_secrets round-trips unchanged" {
    # The strongest form of the test: not a crafted string, the real value
    # this repository ships and enforces on 23 repositories.
    local shipped
    shipped="$(grep -m1 '^pattern_secrets=' "$GITKEEPER_ROOT/.gitkeeper.conf" | cut -d= -f2-)"
    [ -n "$shipped" ]

    parse_config "$GITKEEPER_ROOT/.gitkeeper.conf"

    [ "${GITKEEPER_CONFIG[pattern_secrets]}" = "$shipped" ]
}

@test "an unbalanced quote does not silently drop the rest of the file" {
    # xargs aborts on an unbalanced quote and returns nothing, so the value
    # lands empty and every later key still parses — the file looks fine.
    local file
    file="$(write_config ".gitkeeper.conf" "$(printf 'pattern_secrets=has_one'"'"'quote\nfail_on=error')")"

    parse_config "$file"

    [ "${GITKEEPER_CONFIG[pattern_secrets]}" = "has_one'quote" ]
    [ "$GITKEEPER_FAIL_ON" = "error" ]
}

#------------------------------------------------------------------------------
# Inline comments: still stripped, but only when they are actually comments
#------------------------------------------------------------------------------

@test "an inline comment is still stripped" {
    local file
    file="$(write_config ".gitkeeper.conf" 'fail_on=error   # be strict')"

    parse_config "$file"

    [ "$GITKEEPER_FAIL_ON" = "error" ]
}

@test "a # inside a value is not a comment and is kept" {
    # `#!` is exactly the kind of thing a shell-oriented rule wants to match,
    # and truncating at the first # deletes the pattern rather than the comment.
    local file
    file="$(write_config ".gitkeeper.conf" 'pattern_secrets=^#!/bin/bash$')"

    parse_config "$file"

    [ "${GITKEEPER_CONFIG[pattern_secrets]}" = '^#!/bin/bash$' ]
}

#------------------------------------------------------------------------------
# The overlay path is a second copy of the same parser
#------------------------------------------------------------------------------

@test "a per-directory overlay preserves escapes too" {
    local base overlay
    base="$(write_config ".gitkeeper.conf" 'pattern_secrets=placeholder')"
    overlay="$(write_config "overlay.conf" 'pattern_secrets=st\.[A-Za-z0-9]{20}')"

    parse_config "$base"
    apply_config_overlay "$overlay"

    [ "${GITKEEPER_CONFIG[pattern_secrets]}" = 'st\.[A-Za-z0-9]{20}' ]
}

#------------------------------------------------------------------------------
# trim() is what the parser now leans on, so it gets its own guard
#------------------------------------------------------------------------------

@test "trim keeps a leading dash instead of reading it as a flag" {
    # `echo -e …` swallows its first argument when it looks like a flag.
    [ "$(trim '  -e[0-9]  ')" = '-e[0-9]' ]
}

@test "trim does not interpret backslash sequences" {
    [ "$(trim '  a\tb  ')" = 'a\tb' ]
}
