#!/usr/bin/env bash
# Runs every addon test with lua5.1 and prints a summary. Exits non-zero if any check fails.
set -u
cd "$(dirname "$0")"

failed=0
checks=0
for file in Everlook*/*.lua; do
	luac5.1 -p "$file" || failed=1
done
for test in Everlook*/*_test.lua; do
	if output=$(lua5.1 "$test" 2>&1); then
		:
	else
		failed=1
		echo "$output" | grep -v '^  ok'
	fi
	checks=$((checks + $(echo "$output" | grep -c '^  ok')))
done

files=$(ls Everlook*/*_test.lua | wc -l)
echo "$files test files, $checks checks passed"
[ "$failed" -eq 0 ] || { echo "FAILED"; exit 1; }
