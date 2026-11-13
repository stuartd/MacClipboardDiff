import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CHECK_SCRIPT = ROOT / "scripts/check-release-tag.sh"


class ReleaseEligibilityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="clipdiff-release-tests-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.remote = self.directory / "remote.git"
        self.checkout = self.directory / "checkout"
        self.checkout.mkdir()
        self.environment = dict(
            os.environ,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_TERMINAL_PROMPT="0",
        )
        self.git("init", "--bare", str(self.remote))
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "ClipDiff tests")
        self.git("config", "user.email", "clipdiff-tests@example.invalid")
        scripts = self.checkout / "scripts"
        scripts.mkdir()
        for name in ("retag-latest.sh", "_common.sh"):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        self.git("add", "scripts")
        self.git("commit", "-m", "Initial test commit")
        self.commit = self.git("rev-parse", "HEAD")
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "origin", "main")

    def git(self, *arguments):
        return subprocess.run(
            ["git", *arguments], cwd=self.checkout, env=self.environment,
            text=True, capture_output=True, check=True,
        ).stdout.strip()

    def tag(self, name, *, annotated=False, force=False):
        arguments = ["tag"]
        if annotated:
            arguments += ["-a", "-m", "Annotated test release"]
        if force:
            arguments.append("--force")
        self.git(*arguments, name)
        push = ["push", "--no-follow-tags"]
        if force:
            push.append("--force")
        self.git(*push, "origin", f"refs/tags/{name}")

    def check(self, tag, commit=None, remote="origin"):
        return subprocess.run(
            ["bash", str(CHECK_SCRIPT), tag, commit or self.commit, remote],
            cwd=self.checkout, env=self.environment, text=True, capture_output=True,
        )

    def assert_eligible(self, tag, expected, commit=None):
        result = self.check(tag, commit)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"should_build={str(expected).lower()}\n")

    def test_only_highest_version_builds_even_when_tags_share_a_commit(self):
        self.tag("v0.9.9")
        self.tag("v0.9.10")
        self.assert_eligible("v0.9.9", False)
        self.assert_eligible("v0.9.10", True)

    def test_unpushed_local_tag_cannot_override_remote_highest(self):
        self.tag("v0.9.10")
        self.git("tag", "v999.0.0")
        self.assert_eligible("v0.9.10", True)
        self.assert_eligible("v999.0.0", False)

    def test_annotated_tag_compares_peeled_commit(self):
        self.tag("v0.9.9")
        self.tag("v0.9.10", annotated=True)
        self.assertNotEqual(self.git("rev-parse", "v0.9.10"), self.commit)
        self.assert_eligible("v0.9.10", True)

    def test_moved_tag_rejects_superseded_run(self):
        self.tag("v0.9.10")
        self.git("commit", "--allow-empty", "-m", "Replacement release")
        replacement = self.git("rev-parse", "HEAD")
        self.tag("v0.9.10", force=True)
        self.assert_eligible("v0.9.10", False)
        self.assert_eligible("v0.9.10", True, replacement)

    def test_deleted_tag_is_skipped(self):
        self.tag("v0.9.10")
        self.git("push", "origin", ":refs/tags/v0.9.10")
        self.assert_eligible("v0.9.10", False)

    def test_missing_release_tags_are_skipped(self):
        self.assert_eligible("v0.9.10", False)

    def test_malformed_historical_tag_does_not_override_version_tags(self):
        self.tag("v.09.1101")
        self.tag("v0.9.1113")
        self.assert_eligible("v0.9.1113", True)
        self.assert_eligible("v.09.1101", False)

    def test_remote_query_failure_does_not_authorize_a_build(self):
        result = self.check("v0.9.10", remote=str(self.directory / "missing.git"))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("should_build=true", result.stdout)

    def test_publication_recheck_skips_tag_superseded_during_build(self):
        self.tag("v0.9.10")
        self.assert_eligible("v0.9.10", True)
        self.tag("v0.9.11")
        self.assert_eligible("v0.9.10", False)
        self.assert_eligible("v0.9.11", True)

    def test_retag_helper_ignores_malformed_tag_and_moves_only_highest(self):
        self.tag("v0.9.9")
        self.tag("v0.9.10")
        self.tag("v.09.1101")
        self.git("commit", "--allow-empty", "-m", "New release source")
        replacement = self.git("rev-parse", "HEAD")
        subprocess.run(
            ["bash", "scripts/retag-latest.sh"], cwd=self.checkout,
            env=self.environment, text=True, capture_output=True, check=True,
        )
        remote_tags = dict(
            (ref, commit) for commit, ref in (
                line.split() for line in self.git("ls-remote", "--tags", "--refs", "origin").splitlines()
            )
        )
        self.assertEqual(remote_tags["refs/tags/v0.9.10"], replacement)
        self.assertEqual(remote_tags["refs/tags/v0.9.9"], self.commit)
        self.assertEqual(remote_tags["refs/tags/v.09.1101"], self.commit)
        self.assert_eligible("v0.9.10", True, replacement)


if __name__ == "__main__":
    unittest.main()
