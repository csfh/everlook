# Releasing the addon

A push to `main` that changes `addon/**` runs the addon tests and, when the commits ask for one, publishes a GitHub Release tagged `addon-v<version>`. CI has never played the build, so the smoke list below still happens in the client before that push.

The version in `addon/Everlook/Everlook.toc`, written `## Version: x.y.z`, is what ships when that line changes by hand. The release reads and bumps only that form, and `tests/folders_test.py` fails on any other. Do not tag a release yourself, and do not bump the version past what the release workflow should publish.

## Before the push

1. `just prepush`. It runs the Lua tests, the script tests, the luac checks, and the harness against this repository's `addon/`, then fails if a commit subject since `origin/main` is over 100 characters, because the release notes are made from subjects.
2. `just sync`, then log in on the current client with the modules the push touches turned on.
3. Walk the list below. Skip anything the push did not touch, and say which were skipped.
4. Watch the Lua error display (`/console scriptErrors 1` if it is off) and the Everlook Debug page.

## Smoke list

- Login and `/reload` give no Lua error.
- `/everlook` and `/el` open settings, and every module page opens. Either with extra words still only toggles that page.
- The island shows level and the quest, opens on hover, closes, and a notice appears (a vendor visit or mail).
- Bags open, close, and search (if Bags is on).
- Quest dialog: accept and turn in with quest automation on, and a PvP-flagging quest is left to the player.
- An item tooltip and a creature tooltip show the Everlook id lines once.
- With cinematic skip on: a cinematic and a movie close as they start, a cinematic during a vehicle ride keeps playing with you still in the vehicle, and no "blocked" message appears.
- A full client restart, then login: nothing blank, no error.

## After

The workflow packs the archive and writes the notes from the commit subjects. Check the release page.
