import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "release-notes.py"


class ReleaseNotesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = pathlib.Path(self.directory.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "tag.gpgsign", "false")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.count = 0

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True).strip()

    def commit(self, subject):
        self.count += 1
        (self.repo / "file").write_text(str(self.count))
        self.git("add", "file")
        self.git("commit", "-qm", subject)
        return self.git("rev-parse", "HEAD")

    def run_notes(self, *args, repo=None):
        output = pathlib.Path(self.directory.name) / "notes.md"
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--ref", "HEAD", "--repository", "owner/project",
             "--output", str(output), *args],
            cwd=repo or self.repo, text=True, capture_output=True,
        )
        return result, output.read_text() if output.exists() else ""

    def test_direct_commits_and_same_sha_tags(self):
        self.commit("Initial")
        self.git("tag", "v0.1.7")
        first = self.commit("Fix water")
        second = self.commit("Build app")
        self.git("tag", "v0.1.8")
        result, notes = self.run_notes("--ref", "v0.1.8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("## Changes", notes)
        self.assertNotIn("Initial", notes)
        self.assertLess(notes.index("Fix water"), notes.index("Build app"))
        for sha in (first, second):
            self.assertIn("https://github.com/owner/project/commit/" + sha, notes)
        self.assertIn("/compare/v0.1.7...v0.1.8", notes)

    def test_stable_ancestor_selection(self):
        self.commit("Initial")
        self.git("tag", "v1.0.0")
        self.commit("Stable")
        self.git("tag", "v1.1.0")
        self.commit("Preview")
        self.git("tag", "v1.2.0-rc1")
        self.git("tag", "other-label")
        self.commit("Release")
        result, notes = self.run_notes()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("/compare/v1.1.0...", notes)
        self.assertNotIn("- Stable", notes)
        self.assertIn("- Preview", notes)

    def test_unrelated_tags_and_same_ancestor_aliases(self):
        self.commit("Initial")
        self.git("tag", "v1.0.0")
        self.commit("Previous release")
        self.git("tag", "v1.1.0")
        self.git("tag", "v1.2.0")
        branch = self.git("branch", "--show-current")
        self.git("checkout", "-q", "--orphan", "unrelated")
        self.commit("Unrelated history")
        self.git("tag", "v99.0.0")
        self.git("checkout", "-q", branch)
        self.commit("Current release")
        result, notes = self.run_notes()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("/compare/v1.2.0...", notes)
        self.assertNotIn("Unrelated history", notes)
        self.assertNotIn("Previous release", notes)
        self.assertIn("Current release", notes)

    def test_explicit_unrelated_base_rejected(self):
        self.commit("Initial")
        branch = self.git("branch", "--show-current")
        self.git("checkout", "-q", "--orphan", "unrelated")
        self.commit("Unrelated")
        self.git("tag", "v99.0.0")
        self.git("checkout", "-q", branch)
        result, notes = self.run_notes("--previous-tag", "v99.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ancestor", result.stderr)
        self.assertEqual(notes, "")

    def test_initial_history(self):
        first = self.commit("Initial")
        self.git("tag", "v1.0.0")
        result, notes = self.run_notes("--ref", "v1.0.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("- Initial", notes)
        self.assertIn("/commit/" + first, notes)
        self.assertNotIn("/compare/", notes)

    def test_explicit_empty_range(self):
        self.commit("Initial")
        self.git("tag", "v1.0.0")
        result, notes = self.run_notes("--previous-tag", "v1.0.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No changes since", notes)
        self.assertIn("/compare/v1.0.0...", notes)

    def test_subject_escaping(self):
        self.commit("Initial")
        self.git("tag", "v1.0.0")
        self.commit(r"Fix [link](url) *water* `code` <tag> \\ path ~~strike~~ + item - item")
        result, notes = self.run_notes()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(r"Fix \[link\]\(url\) \*water\* \`code\` &lt;tag&gt; \\\\ path \~\~strike\~\~ \+ item \- item", notes)

    def test_merged_branch_commits_without_merge_subject(self):
        self.commit("Initial")
        self.git("tag", "v1.0.0")
        branch = self.git("branch", "--show-current")
        self.git("checkout", "-qb", "feature")
        self.commit("Branch change")
        self.git("checkout", "-q", branch)
        self.git("merge", "--no-ff", "-m", "Merge feature", "feature")
        result, notes = self.run_notes()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Branch change", notes)
        self.assertNotIn("Merge feature", notes)

    def test_missing_ref(self):
        self.commit("Initial")
        result, notes = self.run_notes("--ref", "missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("resolve", result.stderr.lower())
        self.assertEqual(notes, "")

    def test_shallow_repository(self):
        self.commit("Initial")
        self.commit("Second")
        clone = pathlib.Path(self.directory.name) / "shallow"
        subprocess.check_call(["git", "clone", "-q", "--depth", "1", self.repo.as_uri(), str(clone)])
        result, notes = self.run_notes(repo=clone)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("full history", result.stderr.lower())
        self.assertEqual(notes, "")

    def test_invalid_repository_label(self):
        self.commit("Initial")
        result, _ = self.run_notes("--repository", "owner/project?bad")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
