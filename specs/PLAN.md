# GitKeeper — Master improvement plan

Bugs are fixed. Per-directory config is implemented. This file tracks
everything that remains, in priority order. Each item has a companion
spec file in this directory. Pick any spec and implement it independently
— they do not depend on each other unless noted.

## Status key
- [ ] not started
- [~] in progress
- [x] done

---

## Done
- [x] Bug fixes (stat fallback, print_header collision, config = splitting, CHANGELOG typos, \x27 ERE, all-scope diff, fail_on validation)
- [x] `rules/no_debug.sh` — block debug statements
- [x] Per-directory config overrides (`lib/config.sh`, `lib/scope.sh`, `commands/check.sh`)

---

## Do now — highest value, lowest effort

- [ ] `BATS_TESTS.md`         — test suite for all rules using bats-core
- [ ] `LINT_ERRORS_RULE.md`   — run shellcheck/eslint/etc on staged files
- [ ] `INLINE_IGNORES.md`     — # gitkeeper-ignore suppression comments
- [ ] `RULE_TIMING.md`        — show ms-per-rule in --verbose mode

## Do later — medium value

- [ ] `CUSTOM_RULES_DIR.md`   — GITKEEPER_CUSTOM_RULES_DIR env var
- [ ] `GITKEEPER_IGNORE.md`   — .gitkeeper.ignore path exclusion file
- [ ] `FIX_FLAG.md`           — --fix auto-remediation for safe violations
- [ ] `OUTPUT_JSON.md`        — --output json for CI/editor integrations

## Maybe — nice to have

- [ ] `FILE_ENCODING_RULE.md` — mixed line endings, non-UTF8 bytes
