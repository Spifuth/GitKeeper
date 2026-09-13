# Spec: file_encoding rule

## File to create
  rules/file_encoding.sh  — function rule_file_encoding()

## What it checks
Two distinct problems, both configurable:
  1. Mixed or Windows line endings (CRLF in a file that should be LF)
  2. Non-UTF8 bytes in text files

## Config keys
  file_encoding_check_crlf=1         (default: on)
  file_encoding_check_utf8=1         (default: on)
  file_encoding_exclude=*.png,*.jpg,*.gif,*.ico,*.woff,*.ttf,*.eot,
                         *.pdf,*.zip,*.tar.gz,*.bin,*.exe,*.so,*.dylib
    Comma-separated fnmatch patterns for binary files to skip.
    These are always added to the built-in binary list above.

## Algorithm — CRLF check
  files = get_scope_files scope
  for each file not in exclude list:
    if file contains \r\n (grep -Pl "\r" file):
      add to crlf_violations list

  rule result: fail if any violations and file_encoding_check_crlf=1

## Algorithm — UTF8 check
  for each file not in exclude list:
    run: LC_ALL=C grep -Pl '[^\x00-\x7F]' file
    (matches any non-ASCII byte)
    OR more precise: iconv -f utf-8 -t utf-8 file >/dev/null 2>&1
    If iconv exits non-zero: file is not valid UTF-8.

  Prefer iconv approach — it distinguishes valid multi-byte UTF-8
  from actual garbage bytes. grep approach is simpler but flags
  all non-ASCII including valid UTF-8.

## Output
  ✗ file_encoding — CRLF line endings in 2 file(s)
        src/api/routes.js
        README.md
  ✗ file_encoding — non-UTF8 bytes in 1 file(s)
        data/legacy.csv

## --fix integration (see FIX_FLAG.md)
  rule_fix_file_encoding() — CRLF fix only, not UTF8.
  Fix: sed -i 's/\r//' "$file" (GNU sed) or
       perl -pi -e 's/\r\n/\n/g' "$file" (portable)
  UTF8 fix: not auto-fixable — user must re-encode the file manually.

## Scope awareness
  Only check files that are in the diff scope, not the whole repo.
  This avoids flagging pre-existing encoding issues in untouched files.
  Use get_scope_files, not git ls-files.

## Binary file detection
Before running either check, skip binary files:
  file --mime-encoding "$f" | grep -q binary

Or simpler: check if git considers it binary:
  git diff --cached --numstat -- "$f" | grep -q "^-"
  (binary files show "-" for added/removed lines in numstat)

## Result severity
  CRLF: rule_fail by default. Configurable with file_encoding_crlf_warn=1.
  UTF8: rule_warn by default. Configurable with file_encoding_utf8_fail=1.

Rationale: CRLF is usually an editor config issue (fixable),
UTF8 is often legitimate data that shouldn't block commits.
