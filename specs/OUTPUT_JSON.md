# Spec: --output json

## Goal
Machine-readable output for CI dashboards, editor integrations, and
scripts that parse gitkeeper results. Human output is unchanged unless
--output json is passed.

## Invocation
  gitkeeper check --output json
  gitkeeper check --scope pr --output json 2>/dev/null

## JSON schema
  {
    "version": "1.0.0",
    "scope": "staged",
    "config": ".gitkeeper.conf",
    "files_checked": 12,
    "summary": {
      "passed": 4,
      "warned": 1,
      "failed": 2,
      "skipped": 3
    },
    "exit_code": 2,
    "rules": [
      {
        "name": "secrets",
        "status": "pass",
        "message": null,
        "duration_ms": 14,
        "findings": []
      },
      {
        "name": "no_debug",
        "status": "fail",
        "message": "JS console ×3",
        "duration_ms": 4,
        "findings": [
          {
            "file": "src/api/routes.js",
            "line": "[JS console] console.log(req.body)"
          }
        ]
      }
    ]
  }

## Files to modify

### lib/core.sh
Add a JSON output accumulator. When GITKEEPER_OUTPUT_FORMAT=json,
log_rule() and related functions write to an array instead of stdout.

  GITKEEPER_JSON_RULES=()   # accumulates rule result objects

  log_rule() {
      local rule="$1" status="$2" msg="${3:-}"

      if [[ "${GITKEEPER_OUTPUT_FORMAT:-}" == "json" ]]; then
          # Store for later JSON assembly — do NOT print to stdout
          local entry
          entry="$(printf '{"name":"%s","status":"%s","message":%s,"duration_ms":%s,"findings":[]}' \
              "$rule" "$status" \
              "${msg:+"\"$msg\""}" "${msg:-null}" \
              "${GITKEEPER_LAST_RULE_MS:-0}")"
          GITKEEPER_JSON_RULES+=("$entry")
          return
      fi

      # ... existing human output ...
  }

### commands/check.sh
Add --output to argument parsing:
  --output)       export GITKEEPER_OUTPUT_FORMAT="$2"; shift 2 ;;
  --output=*)     export GITKEEPER_OUTPUT_FORMAT="${1#--output=}"; shift ;;

Validate: only "json" and "text" (default) are accepted.

At the end of cmd_check, before exit:
  if [[ "${GITKEEPER_OUTPUT_FORMAT:-}" == "json" ]]; then
      emit_json_output "$scope" "$root_config" \
          "$total_files" "$grand_passed" "$grand_warned" \
          "$grand_failed" "$grand_skipped" "$exit_code"
  fi

### lib/core.sh — emit_json_output()

  emit_json_output() {
      # Build rules array from GITKEEPER_JSON_RULES
      local rules_json
      rules_json="$(IFS=','; echo "[${GITKEEPER_JSON_RULES[*]}]")"

      # Determine exit code
      local exit_code=0
      [[ $6 -gt 0 ]] && exit_code=2  # failed
      [[ $5 -gt 0 && $(config_fail_on_warn; echo $?) -eq 0 ]] && exit_code=1

      printf '{
  "version": "%s",
  "scope": "%s",
  "config": %s,
  "files_checked": %s,
  "summary": {"passed":%s,"warned":%s,"failed":%s,"skipped":%s},
  "exit_code": %s,
  "rules": %s
}\n' \
          "$GITKEEPER_VERSION" "$1" \
          "${2:+"\"$2\""}" "${2:-null}" \
          "$3" "$4" "$5" "$6" "$7" \
          "$exit_code" \
          "$rules_json"
  }

## Findings capture
Rules currently echo finding lines directly. In JSON mode these need
to be captured. Add to lib/runner.sh:

  GITKEEPER_JSON_FINDINGS=()

  # In run_rule(), capture any stdout from the rule function that
  # starts with a known finding prefix (the "      ${DIM}..." lines)
  # These are sub-findings displayed under the rule result.

  # Rules emit findings with echo -e. In JSON mode, redirect rule
  # stdout to a temp file and parse the finding lines out of it.

## Suppression of all non-JSON stdout
When GITKEEPER_OUTPUT_FORMAT=json, silence ALL human-facing output:
print_header, log_info, log_debug, log_success, log_error, log_warn.
Only the final JSON object goes to stdout.
Errors (die) still go to stderr so the caller can see them.

## Usage in GitHub Actions
  - name: GitKeeper
    id: gitkeeper
    run: ./gitkeeper check --scope pr --output json > gitkeeper.json
    continue-on-error: true

  - name: Annotate PR
    run: |
      cat gitkeeper.json | jq '.rules[] | select(.status=="fail") |
        "::error file=\(.findings[0].file)::\(.message)"'

## Schema versioning
The "version" field in the output is the schema version, not the
gitkeeper binary version. Start at "1.0.0". Increment minor for
additive changes, major for breaking changes.
