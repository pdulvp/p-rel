# prel

A git management toolkit for configuring commit attribution and hooks across repositories.

## Quick Start

Run from any directory in a git repository:

```bash
prel.sh
```

## Commands

### prel usage
Show detailed help for all available commands.

### prel init-authored-hooks (or **hooks**)
Manage git hooks from the prel project.

```bash
prel init-authored-hooks usage          # Show help
prel init-authored-hooks register       # Set core.hooksPath to prel/.githooks
prel init-authored-hooks unregister     # Remove core.hooksPath setting

# Shortcut:
prel hooks register
prel hooks unregister
```

### prel switch-author (or **sa**)
Switch commit author and co-author mode.

```bash
prel switch-author usage    # Show help
prel switch-author          # Show current mode
prel switch-author default  # Use default (no co-author)
prel switch-author claude   # Use Claude mode
prel switch-author mistral  # Use Mistral Vibe mode

# Shortcut:
prel sa claude
prel sa mistral
prel sa default
```

### prel recommit-last (or **recommit**)
Rewrite the last N commits with the current author mode.

```bash
prel recommit-last usage       # Show help
prel recommit-last 3           # Rewrite the last 3 commits
prel recommit-last 3 -n        # Dry run: show what would change

# Shortcut:
prel recommit 3
```

Use it after `prel switch-author` when the last commits were made under the
wrong mode:

```bash
prel sa claude          # pick the mode the commits should have carried
prel recommit-last 3    # replay the last 3 commits under it
```

Each commit is replayed with the committer of the current mode and with its
message run back through the `prepare-commit-msg` hook, so a stale
`Co-Authored-By` trailer is replaced by the one the current mode asks for.
Trailers prel never wrote (real human co-authors) are left alone.

Author identity, author date and commit date are all preserved - only the
committer and the message change. The working tree and the index are never
touched, so this works on a dirty repository. Rewritten commits get new
hashes: the previous HEAD is printed and kept in the reflog, and a branch that
was already pushed needs a force push afterwards. Commit signatures do not
survive the rewrite.

## Direct Script Usage

Scripts can also be run directly from the `scripts/` directory:

```bash
/mnt/Data/Works/prel/scripts/switch-author.sh claude
/mnt/Data/Works/prel/scripts/init-authored-hooks.sh register
/mnt/Data/Works/prel/scripts/recommit-last.sh 3
```

## Configuration Files

- `configs/.gitconfig-claude` - Claude mode attribution
- `configs/.gitconfig-mistral` - Mistral Vibe mode attribution
- `configs/.gitconfig-base` - Base configuration
- `.githooks/prepare-commit-msg` - Hook for adding Co-Authored-By trailers

## How It Works

The prel project maintains its own set of git configuration files and hooks. When you run `prel switch-author`, it sets the `include.path` in your repository's git config to point to the appropriate prel config file, which then includes the base config and sets committer/co-author information.

Git itself does not read `committer.name` / `committer.email`: those record what
the mode *should* commit as, and `prel recommit-last` is what applies them to
commits that were made under another identity.

Similarly, `prel init-authored-hooks register` sets `core.hooksPath` to use the hooks from the prel project, so all repositories can share the same hook implementations.
