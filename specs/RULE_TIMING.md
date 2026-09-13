# Spec: rule timing in --verbose mode

## Goal
When --verbose is passed, show how long each rule took in milliseconds,
printed on the same line as the pass/warn/fail result.

## Target output (verbose mode only)
  ✓ secrets — 12ms
  ✗ no_debug — JS console ×3 — 4ms
  ○ changelog — only runs on push/pr scope — 0ms

## Files to modify

### lib/runner.sh — run_rule()
Wrap the rule call with a timer:

  run_rule() {
      local rule="$1"
      local scope="$2"

      # ... existing load logic ...

      local start_ms end_ms elapsed_ms
      start_ms="$(date +%s%3N 2>/dev/null || date +%s)"

      local result=0
      "rule_${rule}" "$scope" || result=$?

      end_ms="$(date +%s%3N 2>/dev/null || date +%s)"
      elapsed_ms=$(( end_ms - start_ms ))

      # Store for log_rule to append
      export GITKEEPER_LAST_RULE_MS="$elapsed_ms"

      return $result
  }

### lib/core.sh — log_rule()
Append timing when GITKEEPER_VERBOSE=1:

  log_rule() {
      local rule="$1"
      local status="$2"
      local msg="${3:-}"

      local timing=""
      if [[ "$GITKEEPER_VERBOSE" -eq 1 && -n "${GITKEEPER_LAST_RULE_MS:-}" ]]; then
          timing=" — ${GITKEEPER_LAST_RULE_MS}ms"
          unset GITKEEPER_LAST_RULE_MS
      fi

      case "$status" in
          pass) echo -e "  ${GREEN}✓${NC} ${rule}${msg:+ — $msg}${timing}" ;;
          warn) echo -e "  ${YELLOW}⚠ ${NC} ${rule}${msg:+ — $msg}${timing}" ;;
          fail) echo -e "  ${RED}✗${NC} ${rule}${msg:+ — $msg}${timing}" ;;
          skip) echo -e "  ${DIM}○${NC} ${rule}${msg:+ — $msg}${timing}" ;;
      esac
  }

### commands/check.sh — summary
In verbose mode, after the per-rule output, add a "slowest rules" line
if any rule took > 100ms:

  if [[ "$GITKEEPER_VERBOSE" -eq 1 && -n "${GITKEEPER_SLOW_RULES:-}" ]]; then
      echo ""
      log_debug "Slow rules (>100ms): $GITKEEPER_SLOW_RULES"
  fi

Accumulate slow rules in run_all_rules:
  if [[ $elapsed_ms -gt 100 ]]; then
      GITKEEPER_SLOW_RULES="${GITKEEPER_SLOW_RULES:+$GITKEEPER_SLOW_RULES, }${rule} (${elapsed_ms}ms)"
  fi

## Portability note
`date +%s%3N` gives milliseconds on Linux (GNU date).
macOS date does not support %3N. Fallback:
  - Try `python3 -c "import time; print(int(time.time()*1000))"` if available
  - Otherwise fall back to `date +%s` (second precision) and multiply by 1000

Wrap this in a helper in lib/core.sh:
  now_ms() {
      if date +%s%3N &>/dev/null 2>&1; then
          date +%s%3N
      elif command -v python3 &>/dev/null; then
          python3 -c "import time; print(int(time.time()*1000))"
      else
          echo $(( $(date +%s) * 1000 ))
      fi
  }
