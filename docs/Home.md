# 🔐 GitKeeper

> Git quality gate — catch secrets, forbidden files & policy violations before they hit your repo.

GitKeeper runs as a pre-commit hook, pre-push hook, and CI step to enforce repository hygiene automatically.

## Documentation

| Page | Description |
|------|-------------|
| [Installation](Installation.md) | Install GitKeeper and set up hooks |
| [Rules](Rules.md) | All built-in rules and configuration |
| [CI Integration](CI-Integration.md) | GitHub Actions & GitLab CI setup |

## Quick Start

```bash
git clone https://github.com/Spifuth/GitKeeper.git
cd your-project
gitkeeper init
gitkeeper install-hooks
```

From that point on, every `git commit` and `git push` is automatically checked.
