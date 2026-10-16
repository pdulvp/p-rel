#!/usr/bin/env bash
# recommit-last.sh - Rewrite the last N commits with the current author mode
#
# Can be run directly or sourced from prel.sh
# Usage: prel recommit-last [usage|<count> [--dry-run]]
#        OR: ./scripts/recommit-last.sh [usage|<count> [--dry-run]]
# Shortcut: prel recommit [usage|<count> [--dry-run]]

# Shortcut function - recommit is an alias for recommit_last
recommit() {
	recommit_last "$@"
}

# Collect every Co-Authored-By trailer prel knows how to produce, so that the
# trailer left by the previous mode can be dropped before the hook adds the
# one for the current mode. Trailers prel never wrote (real human co-authors)
# are left untouched.
_recommit_last_prel_trailers() {
	local configs_dir="$1"
	local config_file value

	value=$(git config --get commit.coauthor 2>/dev/null || true)
	[ -n "$value" ] && echo "co-authored-by: $value" | tr 'A-Z' 'a-z'

	for config_file in "$configs_dir"/.gitconfig-*; do
		[ -f "$config_file" ] || continue
		value=$(git config --file "$config_file" --get commit.coauthor 2>/dev/null || true)
		[ -n "$value" ] && echo "co-authored-by: $value" | tr 'A-Z' 'a-z'
	done
}

# Strip trailing blank lines and guarantee a single final newline, the way
# git cleans up a message it is handed. Without it the newline that %B adds
# piles up and every rewrite of an already correct commit changes its hash.
_recommit_last_trim() {
	local file="$1" content
	content=$(cat "$file")
	printf '%s\n' "$content" >"$file"
}

recommit_last() {
	local count="${1-usage}"
	local dry_run=0

	if [ "${2-}" = "--dry-run" ] || [ "${2-}" = "-n" ]; then
		dry_run=1
	elif [ -n "${2-}" ]; then
		echo "Error: Unknown option '$2' for recommit-last" >&2
		echo "Try: prel recommit-last usage" >&2
		return 1
	fi

	# If just showing usage, don't need a git repo
	if [ "$count" = "usage" ]; then
		cat <<EOF
recommit-last - Rewrite the last N commits with the current author mode

Usage:
  prel recommit-last usage           Show this help
  prel recommit-last <count>         Rewrite the last <count> commits
  prel recommit-last <count> -n      Show what would change, rewrite nothing

Description:
  Replays the last <count> commits with the committer of the current
  'prel switch-author' mode and with their messages run back through the
  prepare-commit-msg hook, so that a stale Co-Authored-By trailer is replaced
  by the one the current mode asks for.

  Author identity, author date and commit date are all preserved: only the
  committer identity and the message change. The working tree and the index
  are never read or written, so the command is safe to run on a dirty
  repository. Rewritten commits get new hashes; the previous HEAD is printed
  and kept in the reflog so the rewrite can be undone. Commit signatures do
  not survive the rewrite.
EOF
		return 0
	fi

	# Determine PREL_DIR - use exported var if available, otherwise calculate from script location
	local PREL_DIR="${PREL_DIR:-}"
	if [ -z "$PREL_DIR" ]; then
		local SCRIPT_DIR
		SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		PREL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
	fi

	local REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

	if [ -z "$REPO_ROOT" ]; then
		echo "Error: Not in a git repository" >&2
		return 1
	fi

	cd "$REPO_ROOT"

	if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
		echo "Error: '$count' is not a commit count" >&2
		echo "Try: prel recommit-last usage" >&2
		return 1
	fi

	local old_head
	old_head=$(git rev-parse --verify HEAD 2>/dev/null) || {
		echo "Error: No commit to rewrite yet" >&2
		return 1
	}

	local total
	total=$(git rev-list --count HEAD)
	if [ "$count" -gt "$total" ]; then
		echo "Error: Only $total commit(s) on HEAD, cannot rewrite $count" >&2
		return 1
	fi

	# The committer the current mode asks for. Falls back to the plain git
	# identity, which is what a commit made in default mode carries.
	local committer_name committer_email
	committer_name=$(git config --get committer.name 2>/dev/null || git config --get user.name 2>/dev/null || true)
	committer_email=$(git config --get committer.email 2>/dev/null || git config --get user.email 2>/dev/null || true)

	if [ -z "$committer_name" ] || [ -z "$committer_email" ]; then
		echo "Error: No committer identity configured (committer.* or user.*)" >&2
		return 1
	fi

	# The hook that rewrites the message. Without it the messages only lose
	# the trailer of the mode they were committed under.
	local hooks_path hook
	hooks_path=$(git config --get core.hooksPath 2>/dev/null || true)
	[ -n "$hooks_path" ] || hooks_path="$(git rev-parse --git-dir)/hooks"
	hook="$hooks_path/prepare-commit-msg"
	if [ ! -x "$hook" ]; then
		echo "Warning: No executable prepare-commit-msg hook in $hooks_path" >&2
		echo "Warning: messages will lose their prel trailer without gaining a new one" >&2
		echo "Warning: run 'prel hooks register' first to add the trailer" >&2
		hook=""
	fi

	local mode
	mode=$(git config --local --get include.path 2>/dev/null || true)
	if [ -n "$mode" ]; then
		mode=$(basename "$mode" | sed 's|^.gitconfig-||')
	else
		mode="default"
	fi

	echo "mode: $mode"
	echo "committer: $committer_name <$committer_email>"
	echo "co-author: $(git config --get commit.coauthor || echo '(none)')"
	echo "rewriting: last $count commit(s) of $(git rev-parse --abbrev-ref HEAD)"
	echo ""

	local tmpdir
	tmpdir=$(mktemp -d) || return 1
	local msg_file="$tmpdir/msg"
	local drop_file="$tmpdir/drop"

	_recommit_last_prel_trailers "$PREL_DIR/configs" >"$drop_file"

	local -a range=()
	mapfile -t range < <(git rev-list --reverse -n "$count" HEAD)

	# Old hash -> new hash, so that each commit is rebuilt onto the rewrite of
	# its parent. Parents outside the range are kept as they are.
	local -A rewritten=()
	local sha new_sha tree parents parent author_name author_email author_date commit_date
	local -a parent_args

	for sha in "${range[@]}"; do
		tree=$(git rev-parse "$sha^{tree}")
		parents=$(git rev-list --parents -n 1 "$sha" | cut -s -d' ' -f2-)

		parent_args=()
		for parent in $parents; do
			if [ -n "${rewritten[$parent]-}" ]; then
				parent_args+=(-p "${rewritten[$parent]}")
			else
				parent_args+=(-p "$parent")
			fi
		done

		IFS=$'\x1f' read -r author_name author_email author_date commit_date \
			< <(git log -1 --format='%an%x1f%ae%x1f%aI%x1f%cI' "$sha")

		git log -1 --format='%B' "$sha" >"$msg_file"

		# Drop the trailer of the mode this commit was made under, then let the
		# hook add the one the current mode asks for.
		awk 'NR==FNR { drop[$0]; next }
			{ key = tolower($0); sub(/[ \t]+$/, "", key); if (key in drop) next; print }' \
			"$drop_file" "$msg_file" >"$msg_file.new"
		mv "$msg_file.new" "$msg_file"
		_recommit_last_trim "$msg_file"

		if [ -n "$hook" ]; then
			if [ "${#parent_args[@]}" -gt 2 ]; then
				"$hook" "$msg_file" merge || true
			else
				"$hook" "$msg_file" message || true
			fi
			_recommit_last_trim "$msg_file"
		fi

		if [ "$dry_run" -eq 1 ]; then
			echo "  $(git rev-parse --short "$sha")  $(head -1 "$msg_file")"
			sed -n 's/^[Cc]o-[Aa]uthored-[Bb]y:/           co-author:/p' "$msg_file"
			rewritten[$sha]="$sha"
			continue
		fi

		new_sha=$(GIT_AUTHOR_NAME="$author_name" \
			GIT_AUTHOR_EMAIL="$author_email" \
			GIT_AUTHOR_DATE="$author_date" \
			GIT_COMMITTER_NAME="$committer_name" \
			GIT_COMMITTER_EMAIL="$committer_email" \
			GIT_COMMITTER_DATE="$commit_date" \
			git commit-tree "$tree" "${parent_args[@]}" <"$msg_file") || {
			echo "Error: Failed to rewrite $sha" >&2
			rm -rf "$tmpdir"
			return 1
		}

		echo "  $(git rev-parse --short "$sha") -> $(git rev-parse --short "$new_sha")  $(head -1 "$msg_file")"
		rewritten[$sha]="$new_sha"
	done

	rm -rf "$tmpdir"

	local new_head="${rewritten[${range[-1]}]}"

	if [ "$dry_run" -eq 1 ]; then
		echo ""
		echo "Dry run: nothing rewritten"
		return 0
	fi

	if [ "$new_head" = "$old_head" ]; then
		echo ""
		echo "Already committed as $mode mode, nothing to rewrite"
		return 0
	fi

	git update-ref -m "prel recommit-last $count ($mode)" HEAD "$new_head" "$old_head" || {
		echo "Error: Failed to move HEAD to $new_head" >&2
		return 1
	}

	echo ""
	echo "Rewrote $count commit(s), HEAD is now $(git rev-parse --short HEAD)"
	echo "Previous HEAD: $old_head"
	echo "To undo: git update-ref HEAD $old_head"

	local upstream
	upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
	if [ -n "$upstream" ] && [ "$(git rev-list --count "$upstream" "^$new_head")" -gt 0 ]; then
		echo "Note: $upstream still holds the old commits, it needs a force push"
	fi
}

# If this script is run directly (not sourced), call the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	recommit_last "$@"
fi
