#!/usr/bin/env bash
# switch-author.sh - Switch commit author mode
#
# Can be run directly or sourced from prel.sh
# Usage: prel switch-author [usage|default|claude|mistral]
#        OR: ./scripts/switch-author.sh [usage|default|claude|mistral]

switch_author() {
	local action="${1-}"
	
	# Determine PREL_DIR - use exported var if available, otherwise calculate from script location
	local PREL_DIR="${PREL_DIR:-}"
	if [ -z "$PREL_DIR" ]; then
		local SCRIPT_DIR
		SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		PREL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
	fi
	
	# If just showing usage, don't need a git repo
	if [ "$action" = "usage" ]; then
		cat <<EOF
switch-author - Switch commit author mode

Usage:
  prel switch-author usage    Show this help
  prel switch-author          Show current mode
  prel switch-author default  Use default (no co-author)
  prel switch-author claude   Use Claude mode
  prel switch-author mistral  Use Mistral AI mode

Description:
  Switches the commit author and co-author settings for the current repository.
  Settings are read from prel config files.
EOF
		return 0
	fi
	
	local REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
	
	if [ -z "$REPO_ROOT" ]; then
		echo "Error: Not in a git repository" >&2
		return 1
	fi
	
	cd "$REPO_ROOT"
	
	# If no action provided, show current state
	if [ -z "$action" ]; then
		local current_mode
		current_mode=$(git config --local --get include.path 2>/dev/null || true)
		if [ -n "$current_mode" ]; then
			current_mode=$(basename "$current_mode" | sed 's|^.gitconfig-||')
		else
			current_mode="default"
		fi
		
		echo "mode: $current_mode"
		echo "committer: $(git config --get committer.name || echo '(author, unset)')"
		echo "co-author: $(git config --get commit.coauthor || echo '(none)')"
		echo "hooks: $(git config --get core.hooksPath || echo '(default)')"
		return 0
	fi
	
	case "$action" in
		default)
			git config --local --unset-all include.path 2>/dev/null || true
			echo "Switched to default mode"
			;;
		claude|mistral)
			local configs_dir="$PREL_DIR/configs"
			
			# Check if the mode file exists in prel configs
			if [ ! -f "$configs_dir/.gitconfig-$action" ]; then
				echo "Error: No .gitconfig-$action found in prel project ($configs_dir)" >&2
				return 1
			fi
			
			# Use absolute path to the config file
			local config_file="$configs_dir/.gitconfig-$action"
			git config --local --replace-all include.path "$config_file"
			echo "Switched to $action mode"
			;;
		*)
			echo "Error: Unknown mode '$action' for switch-author" >&2
			echo "Try: prel switch-author usage" >&2
			return 1
			;;
	esac
	
	# Show current state
	local current_mode
	current_mode=$(git config --local --get include.path 2>/dev/null || true)
	if [ -n "$current_mode" ]; then
		current_mode=$(basename "$current_mode" | sed 's|^.gitconfig-||')
	else
		current_mode="default"
	fi
	
	if [ "$action" = "default" ]; then
		echo "Switched to default mode"
	else
		echo "Switched to $action mode"
	fi
	
	echo "mode: $current_mode"
	echo "committer: $(git config --get committer.name || echo '(author, unset)')"
	echo "co-author: $(git config --get commit.coauthor || echo '(none)')"
	echo "hooks: $(git config --get core.hooksPath || echo '(default)')"
}

# If this script is run directly (not sourced), call the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	switch_author "$@"
fi
