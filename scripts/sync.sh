#!/bin/bash
set -euo pipefail

addon="$(cd "$(dirname "$0")/../addon" && pwd)"
addons="${EVERLOOK_ADDONS_DIR:-}"
if [ -z "$addons" ]; then
	echo "addon-sync: set EVERLOOK_ADDONS_DIR to your World of Warcraft Interface/AddOns folder" >&2
	exit 1
fi

mkdir -p "$addons"

# Moves a real folder aside so the link can take its place. Prints where the
# old contents are now, which is the destination itself when nothing moved.
set_aside() {
	local dest="$1" name="$2"
	if [ -L "$dest" ] || [ ! -e "$dest" ]; then
		echo "$dest"
		return
	fi
	if [ ! -d "$dest" ]; then
		echo "addon-sync: $dest exists and is not a directory" >&2
		exit 1
	fi
	local backup
	backup="$(mktemp -d "${dest}.backup.XXXXXX")"
	mv "$dest" "$backup/$name"
	echo "addon-sync: previous addon saved at $backup/$name" >&2
	echo "$backup/$name"
}

for source in "$addon"/Everlook "$addon"/Everlook_*; do
	[ -d "$source" ] || continue
	name="$(basename "$source")"
	dest="$addons/$name"
	set_aside "$dest" "$name" >/dev/null
	ln -sfnT "$source" "$dest"
	echo "$dest -> $source"
done

# A module folder that was removed or renamed leaves a dangling link behind.
for dest in "$addons"/Everlook_*; do
	if [ -L "$dest" ] && [ ! -e "$dest" ]; then
		target="$(readlink "$dest")"
		case "$target" in
			"$addon"/*) rm "$dest" && echo "addon-sync: removed $dest, whose folder is gone" ;;
		esac
	fi
done
