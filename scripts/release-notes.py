#!/usr/bin/env python3
"""Write release notes from the commits between stable tags."""

import argparse
import html
import pathlib
import re
import subprocess
import sys
import urllib.parse


class NotesError(Exception):
    pass


def git(*args):
    result = subprocess.run(
        ["git", *args], text=True, encoding="utf-8", errors="replace", capture_output=True,
    )
    if result.returncode:
        raise NotesError(result.stderr.strip() or "Git command failed")
    return result.stdout.strip()


def resolve(ref):
    try:
        return git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}")
    except NotesError as error:
        raise NotesError("Cannot resolve commit ref: " + ref) from error


def previous_stable(target):
    candidates = []
    tags = git("for-each-ref", "--merged=" + target, "--format=%(refname:strip=2)", "refs/tags")
    for tag in tags.splitlines():
        match = re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag)
        if not match:
            continue
        commit = resolve(tag)
        if commit == target:
            continue
        distance = int(git("rev-list", "--count", commit + ".." + target))
        version = tuple(-int(part) for part in match.groups())
        candidates.append((distance, version, tag, commit))
    if not candidates:
        return None
    _, _, tag, commit = min(candidates)
    return tag, commit


def escape(text):
    return re.sub(r"([\\`*_{}\[\]()#!|~+.=\-])", r"\\\1", html.escape(text, quote=False))


def notes(ref, repository, previous_tag=None):
    if git("rev-parse", "--is-shallow-repository") == "true":
        raise NotesError("Release notes require full history. Fetch with --unshallow and fetch tags.")
    target = resolve(ref)
    previous = (previous_tag, resolve(previous_tag)) if previous_tag is not None else previous_stable(target)
    if previous:
        # An empty explicit range is valid. An unrelated ref is not a release base.
        try:
            git("merge-base", "--is-ancestor", previous[1], target)
        except NotesError as error:
            raise NotesError("Previous tag must be an ancestor of the target ref") from error
    revision = previous[1] + ".." + target if previous else target
    commits = git("log", "--reverse", "--topo-order", "--no-merges", "--format=%H%x00%s", revision, "--")
    base = "https://github.com/" + repository
    lines = ["## Changes", ""]
    for record in commits.split("\n") if commits else ():
        sha, subject = record.split("\0", 1)
        lines.append("- " + escape(subject) + " ([" + sha[:7] + "](" + base + "/commit/" + sha + "))")
    if not commits:
        lines.append("No changes since " + escape(previous[0]) + "." if previous else "No changes in this release.")
    lines.append("")
    if previous:
        compare = urllib.parse.quote(previous[0], safe="") + "..." + urllib.parse.quote(ref, safe="")
        lines.append("[Full changelog](" + base + "/compare/" + compare + ")")
    else:
        lines.append("[Release commit](" + base + "/commit/" + target + ")")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", required=True, help="Release tag or commit ref")
    parser.add_argument("--repository", required=True, help="GitHub owner/repository")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--previous-tag", help="Use this release base instead of selecting a stable tag")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", args.repository):
        parser.error("Repository must be owner/repository")
    try:
        result = notes(args.ref, args.repository, args.previous_tag)
        args.output.write_text(result, encoding="utf-8")
    except (NotesError, OSError) as error:
        print("release-notes: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
