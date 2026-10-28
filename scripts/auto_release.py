#!/usr/bin/env python3
"""Pick the next addon version from commit messages.

Each push is read as conventional commits. The biggest change wins: a breaking change is a major bump,
feat is minor, fix, perf, refactor and revert are patch. docs, test, chore, ci,
style and build do not release. A subject that is not a conventional commit
counts as patch, so a change never ships silently without a version.
Before 1.0.0 a breaking change bumps minor, so it never jumps to 1.0.0 by accident.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
# The one form of the version line: the bump writes it, and the hand-set check reads only it.
TOC_VERSION = re.compile(r"^(## Version: )(\S+)", re.MULTILINE)
ZERO_SHA = "0" * 40
VERSION_FILE = "Everlook/Everlook.toc"
TAG_PREFIX = "addon-v"
# What a release counts, from the root addon/: the addon folders, and not the tests that sit beside them.
RELEASE_PATHS = (".", ":(exclude)tests")


LEVELS = ("patch", "minor", "major")
CONVENTIONAL = re.compile(r"^(\w+)(\([^)]*\))?(!)?:\s")
BREAKING_BODY = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)
LEVEL_BY_TYPE = {
    "feat": "minor",
    "fix": "patch",
    "perf": "patch",
    "refactor": "patch",
    "revert": "patch",
}
SILENT_TYPES = {"docs", "test", "tests", "chore", "ci", "style", "build"}
RELEASE_SUBJECT = re.compile(r"^chore: release ")


def bump_version(version: str, level: str = "patch") -> str:
    match = SEMVER.fullmatch(version.strip())
    if match is None:
        raise ValueError(f"unsupported version {version!r}")
    major, minor, patch = (int(part) for part in match.groups())
    if level == "major" and major == 0:
        level = "minor"
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def commit_level(subject: str, body: str = "") -> str | None:
    """The bump one commit asks for, or None when it does not release."""
    match = CONVENTIONAL.match(subject)
    if match is None:
        return "patch"
    kind = match.group(1).lower()
    if match.group(3) == "!" or BREAKING_BODY.search(body):
        return "major"
    if kind in SILENT_TYPES:
        return None
    return LEVEL_BY_TYPE.get(kind, "patch")


def highest(levels: list[str | None]) -> str | None:
    found = [level for level in levels if level is not None]
    return max(found, key=LEVELS.index) if found else None


def bump_addon(root: Path, level: str = "patch") -> str:
    toc_path = root / VERSION_FILE
    text = toc_path.read_text()
    match = TOC_VERSION.search(text)
    if match is None:
        raise ValueError("Everlook/Everlook.toc has no Version field")
    version = bump_version(match.group(2), level)
    toc_path.write_text(TOC_VERSION.sub(rf"\g<1>{version}", text, count=1))
    return version


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True)


def commit_known(root: Path, sha: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{sha}^{{commit}}"], capture_output=True
    ).returncode == 0


def commits_touching(root: Path, before: str, after: str) -> list[tuple[str, str]]:
    """Subject and body of each commit in before..after that touches what a release ships.

    The root is addon/, so the harness, the scripts and the site beside it never count, and nor does addon/tests.
    """
    out = git(root, "log", "--format=%s%x1f%b%x1e", f"{before}..{after}", "--", *RELEASE_PATHS)
    commits = []
    for record in out.split("\x1e"):
        if record.strip():
            subject, _, body = record.partition("\x1f")
            commits.append((subject.strip(), body.strip()))
    return commits


NOTE_SECTIONS = (
    ("major", "Breaking changes"),
    ("minor", "Features"),
    ("patch", "Fixes and improvements"),
)


def release_notes(root: Path, since: str) -> str:
    """Markdown notes for the commits that touched the addon since a ref.

    Housekeeping commits and release commits are left out. A missing or empty
    ref falls back to the latest commit, so a first release still has notes.
    """
    if since in ("", ZERO_SHA):
        out = git(root, "log", "-1", "--format=%h%x1f%s%x1f%b%x1e", "--", *RELEASE_PATHS)
    else:
        out = git(root, "log", f"--format=%h%x1f%s%x1f%b%x1e", f"{since}..HEAD", "--", *RELEASE_PATHS)
    grouped: dict[str, list[str]] = {level: [] for level, _ in NOTE_SECTIONS}
    thanks: dict[str, str] = {}
    for record in out.split("\x1e"):
        if not record.strip():
            continue
        short, _, rest = record.strip().partition("\x1f")
        subject, _, body = rest.partition("\x1f")
        subject = subject.strip()
        if RELEASE_SUBJECT.match(subject):
            continue
        level = commit_level(subject, body)
        if level is None:
            continue
        match = CONVENTIONAL.match(subject)
        text = subject[match.end():] if match else subject
        grouped[level].append(f"- {text} ({short})")
        # A commit that fixes something a person reported names them in a `Reported-by:` line.
        for name in re.findall(r"^Reported-by:[ \t]*(.+)$", body, re.MULTILINE):
            if name.strip():
                thanks[name.strip().lower()] = name.strip()  # the log runs newest first, so the oldest spelling is kept
    sections = [
        f"## {title}\n\n" + "\n".join(grouped[level])
        for level, title in NOTE_SECTIONS
        if grouped[level]
    ]
    if sections and thanks:
        sections.append("## Thanks\n\nFor reporting what these fix: " + ", ".join(thanks[key] for key in sorted(thanks)) + ".")
    return "\n\n".join(sections) + "\n" if sections else "Maintenance release.\n"


def latest_tag(root: Path, prefix: str, ref: str) -> str | None:
    try:
        out = subprocess.check_output(
            ["git", "-C", str(root), "describe", "--tags", "--abbrev=0", "--match", f"{prefix}*", ref],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        return out.strip() or None
    except subprocess.CalledProcessError:
        return None


def release_base(root: Path, tag_prefix: str | None, version_file: str, ref: str) -> str | None:
    """Where counting starts: the last release tag.

    Without one, the last "chore: release" commit on the version file marks the
    same point, so work after it is still counted when a push fails to release it.
    """
    tag = latest_tag(root, tag_prefix, ref) if tag_prefix else None
    if tag is not None:
        return tag
    for line in git(root, "log", "--format=%H%x1f%s", ref, "--", version_file).splitlines():
        sha, _, subject = line.partition("\x1f")
        if RELEASE_SUBJECT.match(subject):
            return sha
    return None


def plan_release(
    root: Path,
    before: str,
    after: str,
    version_file: str,
    tag_prefix: str | None = None,
) -> tuple[str | None, bool]:
    """Return (bump level, whether to release).

    Commits are counted from the last release (see release_base), so
    a push whose tests failed or whose run was cancelled still counts in the
    next one. With no release at all, only this push counts. A level of None
    with release True means the push already set the version by hand, so the
    release ships it as it is.
    """
    if before not in ("", ZERO_SHA) and not commit_known(root, before):
        # A force push replaced the history, so the runner never fetched the old tip.
        before = ZERO_SHA
    base = release_base(root, tag_prefix, version_file, after)
    if base is None and before in ("", ZERO_SHA):
        return "patch", True
    commits = commits_touching(root, base or before, after)
    ours = [(s, b) for s, b in commits if not RELEASE_SUBJECT.match(s)]
    if not ours:
        return None, False
    diff = "" if before in ("", ZERO_SHA) else git(root, "diff", before, after, "--", version_file)
    if version_field_changed(diff):
        return None, True
    level = highest([commit_level(s, b) for s, b in ours])
    return level, level is not None


def version_value(line_body: str) -> str | None:
    match = TOC_VERSION.match(line_body)
    return match.group(2) if match else None


def version_field_changed(diff: str) -> bool:
    old = None
    new = None
    for line in diff.splitlines():
        if not line.startswith(("+", "-")) or line.startswith(("+++", "---")):
            continue
        value = version_value(line[1:].strip())
        if value is None:
            continue
        if line.startswith("-"):
            old = value
        else:
            new = value
    return old != new and (old is not None or new is not None)


def write_output(version: str, bumped: bool, release: bool, level: str | None) -> None:
    lines = (
        f"version={version}\n"
        f"bumped={'true' if bumped else 'false'}\n"
        f"release={'true' if release else 'false'}\n"
        f"level={level or ''}\n"
    )
    sys.stdout.write(lines)
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a", encoding="utf-8") as handle:
            handle.write(lines)


def current_addon_version(root: Path) -> str:
    match = TOC_VERSION.search((root / VERSION_FILE).read_text())
    if match is None:
        raise ValueError("addon/Everlook/Everlook.toc has no Version field")
    return match.group(2)


def maybe_bump(root: Path, before: str, after: str) -> tuple[str, bool, bool, str | None]:
    level, release = plan_release(root, before, after, VERSION_FILE, TAG_PREFIX)
    if level is not None:
        return bump_addon(root, level), True, True, level
    return current_addon_version(root), False, release, None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("maybe-bump", "release-notes"))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1] / "addon")
    parser.add_argument("--before", default=ZERO_SHA)
    parser.add_argument("--after", default="HEAD")
    parser.add_argument("--since", default="")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    if args.command == "release-notes":
        since = args.since
        if latest_tag(root, TAG_PREFIX, "HEAD") is None:
            since = release_base(root, TAG_PREFIX, VERSION_FILE, "HEAD") or since
        sys.stdout.write(release_notes(root, since))
        return 0
    version, bumped, release, level = maybe_bump(root, args.before, args.after)
    write_output(version, bumped, release, level)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
