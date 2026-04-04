# Spec: .gitkeeper.ignore file

## Goal
A file that lists paths/patterns to exclude from ALL gitkeeper checks,
similar to .gitignore. Useful for vendored code, generated files, and
directories that should never be linted regardless of rule config.

## File location
  .gitkeeper.ignore   (in repo root, next to .gitkeeper.conf)

Override location:
  ignore_file=/path/to/custom.ignore   (in .gitkeeper.conf)

## File format
  # Comments start with #
  # Blank lines ignored

  vendor/               # trailing slash = directory prefix match
  generated/**          # glob patterns supported
  *.pb.go               # fnmatch-style patterns
  src/legacy/old.js     # exact relative path
  !src/legacy/new.js    # negation: un-ignore a path (applied last)

## Files to create/modify

### lib/ignore.sh  (NEW FILE)

  GITKEEPER_IGNORE_PATTERNS=()

  load_ignore_file() {
      local ignore_file="${1:-}"

      # Resolve ignore file path
      if [[ -z "$ignore_file" ]]; then
          ignore_file="$(config_get ignore_file '.gitkeeper.ignore')"
      fi

      local repo_root
      repo_root="$(get_repo_root)"
      local full_path="$repo_root/$ignore_file"

      if [[ ! -f "$full_path" ]]; then
          return 0
      fi

      log_debug "ignore: loading $full_path"

      GITKEEPER_IGNORE_PATTERNS=()
      while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
          GITKEEPER_IGNORE_PATTERNS+=("$(trim "$line")")
      done < "$full_path"
  }

  # Returns 0 if the file should be ignored, 1 if it should be checked.
  # Negation patterns (!) are processed after positive patterns,
  # matching .gitignore semantics.
  is_ignored_path() {
      local file="$1"
      local matched=0

      for pattern in "${GITKEEPER_IGNORE_PATTERNS[@]}"; do
          local negate=0
          [[ "$pattern" == !* ]] && negate=1 && pattern="${pattern:1}"

          if _path_matches_pattern "$file" "$pattern"; then
              matched=$negate  # 0=ignored, 1=not-ignored
          fi
      done

      return $(( 1 - matched ))  # flip: 0=ignored means return 0
  }

  _path_matches_pattern() {
      local file="$1"
      local pattern="$2"

      # Directory prefix (trailing slash)
      if [[ "$pattern" == */ ]]; then
          [[ "$file" == "${pattern%/}"/* || "$file" == "${pattern%/}" ]] && return 0
          return 1
      fi

      # Use bash glob matching
      # shellcheck disable=SC2254
      case "$file" in
          $pattern) return 0 ;;
      esac

      # Also match against just the filename (like .gitignore)
      local basename="${file##*/}"
      case "$basename" in
          $pattern) return 0 ;;
      esac

      return 1
  }

### lib/scope.sh — filter ignored paths

In get_scope_files(), after fetching raw_files, add a filter step:

  # Apply .gitkeeper.ignore
  _apply_gitkeeper_ignore() {
      while IFS= read -r file; do
          [[ -z "$file" ]] && continue
          is_ignored_path "$file" || echo "$file"
      done
  }

  # In get_scope_files, pipe through both filters:
  echo "$raw_files" | _apply_gitkeeper_ignore | _apply_file_filter

### gitkeeper main / cmd_check
Load the ignore file early, after parse_config:

  load_ignore_file

### commands/explain.sh
After listing files in scope, note if any were excluded:
  if [[ ${#GITKEEPER_IGNORE_PATTERNS[@]} -gt 0 ]]; then
      log_info "Ignore patterns: ${#GITKEEPER_IGNORE_PATTERNS[@]} active"
  fi

## source lib/ignore.sh
Add to the load order in gitkeeper main:
  source "$GITKEEPER_LIB_DIR/ignore.sh"

## Edge cases
- Pattern with leading / means repo root relative (strip the /).
- ** means any depth (convert to * for bash glob, or use a loop).
- Empty GITKEEPER_IGNORE_PATTERNS = no filtering, zero overhead.
- Ignored files are still counted in "Files:" header but skipped in rules.
  Consider: "Files: 12 (3 ignored)" in --verbose mode.
