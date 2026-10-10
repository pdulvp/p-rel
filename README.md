# prel

A git management toolkit for configuring commit attribution and hooks across repositories.

## Quick Start

Run from any directory in a git repository:

```bash
/mnt/Data/Works/prel/prel.sh
```

## Commands

### prel usage
Show detailed help for all available commands.

### prel init-authored-hooks
Manage git hooks from the prel project.

```bash
prel init-authored-hooks usage          # Show help
prel init-authored-hooks register       # Set core.hooksPath to prel/.githooks
prel init-authored-hooks unregister     # Remove core.hooksPath setting
```

### prel switch-author
Switch commit author and co-author mode.

```bash
prel switch-author usage    # Show help
prel switch-author          # Show current mode
prel switch-author default  # Use default (no co-author)
prel switch-author claude   # Use Claude mode
prel switch-author mistral  # Use Mistral Vibe mode
```

## Direct Script Usage

Scripts can also be run directly from the `scripts/` directory:

```bash
/mnt/Data/Works/prel/scripts/switch-author.sh claude
/mnt/Data/Works/prel/scripts/init-authored-hooks.sh register
```

## Configuration Files

- `configs/.gitconfig-claude` - Claude mode attribution
- `configs/.gitconfig-mistral` - Mistral Vibe mode attribution
- `configs/.gitconfig-base` - Base configuration
- `.githooks/prepare-commit-msg` - Hook for adding Co-Authored-By trailers

## How It Works

The prel project maintains its own set of git configuration files and hooks. When you run `prel switch-author`, it sets the `include.path` in your repository's git config to point to the appropriate prel config file, which then includes the base config and sets committer/co-author information.

Similarly, `prel init-authored-hooks register` sets `core.hooksPath` to use the hooks from the prel project, so all repositories can share the same hook implementations.
