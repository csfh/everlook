#!/usr/bin/env bash
# Symlinks every Everlook* folder in this repo into the game's AddOns folder.
# Usage: ./link.sh [AddOns folder]
set -eu
cd "$(dirname "$0")"

addons="${1:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns}"
[ -d "$addons" ] || { echo "No AddOns folder at: $addons" >&2; exit 1; }

for folder in Everlook*/; do
	name="${folder%/}"
	target="$addons/$name"
	if [ -L "$target" ] || [ ! -e "$target" ]; then
		ln -sfn "$PWD/$name" "$target"
		echo "linked $name"
	else
		echo "skipped $name: a real folder is already there" >&2
	fi
done
