# Changelog

All notable changes to GitKeeper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2026-01-06

### Added
- Modular architecture with lib/, commands/, ules/ directories
- Core CLI commands: check, init, configure, install-hooks, explain, help
- Built-in rules: secrets, forbid_files, changelog, version, readme, todos, branch_name, large_files, merge_conflict
- Scopes: staged, push, pr, stash, range
- Interactive configuration wizard (gitkeeper configure)
- Git hooks integration: pre-commit and pre-push
- Bash and Zsh shell completions
- Install/uninstall script with PATH setup
- GitHub Actions and GitLab CI integration examples
- Custom rule API for extending with your own rules