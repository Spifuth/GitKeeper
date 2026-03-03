# CI Integration

GitKeeper can run as a required status check on every pull request.

## GitHub Actions

```yaml
name: GitKeeper
on: [pull_request]

jobs:
  gitkeeper:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # Full history needed for diff

      - name: Run GitKeeper
        env:
          GITKEEPER_PR_BASE: origin/${{ github.base_ref }}
        run: |
          git clone https://github.com/Spifuth/GitKeeper.git /tmp/gitkeeper
          export PATH="$PATH:/tmp/gitkeeper"
          chmod +x /tmp/gitkeeper/gitkeeper
          gitkeeper check --scope pr
```

## GitLab CI

```yaml
gitkeeper:
  stage: test
  script:
    - git clone https://github.com/Spifuth/GitKeeper.git /tmp/gitkeeper
    - export PATH="$PATH:/tmp/gitkeeper"
    - chmod +x /tmp/gitkeeper/gitkeeper
    - export GITKEEPER_PR_BASE="origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
    - gitkeeper check --scope pr
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All checks passed |
| `1` | Warnings (fails only if `fail_on=warn`) |
| `2` | Errors — checks failed |

## Tips

- Use `GITKEEPER_PR_BASE` env var to specify the base branch for PR checks
- Set `fail_on=warn` in CI for stricter enforcement
- Use `gitkeeper explain --scope pr` to debug what will be checked
