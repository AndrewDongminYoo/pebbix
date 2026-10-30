"""Exercise public snapshot boundaries with disposable committed Git repositories."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tool import export_public_snapshot


class PublicSnapshotTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.repo = self.root / "private"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Snapshot fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.write("tool/public_snapshot_paths.txt", "README.md\nLICENSE\nlib/**\n")
        self.write("README.md", "committed public instructions\n")
        self.write("LICENSE", "fixture licensing scope\n")
        self.write("lib/game.dart", "committed game source\n")
        self.write("docs/private-review.md", "private correspondence\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture source")
        self.output = self.root / "public"

    def git(self, *arguments: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(self.repo), *arguments], text=True
        ).strip()

    def write(self, name: str, content: str) -> None:
        target = self.repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def test_exports_committed_selected_bytes_without_private_or_local_state(
        self,
    ) -> None:
        self.write("README.md", "uncommitted change\n")
        self.write("lib/local.dart", "untracked file\n")
        self.write("local-settings.json", "local fixture setting\n")
        export_public_snapshot.export_snapshot(self.repo, "HEAD", self.output)
        self.assertEqual(
            (self.output / "README.md").read_text(), "committed public instructions\n"
        )
        self.assertEqual(
            sorted(
                p.relative_to(self.output).as_posix()
                for p in self.output.rglob("*")
                if p.is_file()
            ),
            ["LICENSE", "README.md", "lib/game.dart"],
        )
        self.assertFalse((self.output / ".git").exists())

    def test_existing_destination_is_preserved(self) -> None:
        self.output.mkdir()
        sentinel = self.output / "keep.txt"
        sentinel.write_text("keep\n")
        with self.assertRaises(FileExistsError):
            export_public_snapshot.export_snapshot(self.repo, "HEAD", self.output)
        self.assertEqual(sentinel.read_text(), "keep\n")

    def test_public_art_selection_retains_provenance_without_private_qa(self) -> None:
        selection = Path(export_public_snapshot.__file__).with_name(
            "public_snapshot_paths.txt"
        )
        self.write("tool/public_snapshot_paths.txt", selection.read_text())
        provenance = "docs/notes/art/and-102-production-art-pack.md"
        proof = "docs/notes/art/and-102-bubble-22px-proof.png"
        historical_qa = "docs/notes/art/defender-motion-validation.md"
        unlisted_draft = "docs/notes/art/unlisted-draft.md"
        self.write(provenance, "Retained art provenance fixture.\n")
        self.write(proof, "Retained proof fixture bytes.\n")
        self.write(historical_qa, "[Local recording](../../../build/motion.webm)\n")
        self.write(unlisted_draft, "Unreviewed art draft fixture.\n")
        self.git("add", "tool/public_snapshot_paths.txt", "docs/notes/art")
        self.git("commit", "-qm", "Add public selection fixtures")

        export_public_snapshot.export_snapshot(self.repo, "HEAD", self.output)

        self.assertEqual(
            (self.output / provenance).read_bytes(),
            (self.repo / provenance).read_bytes(),
        )
        self.assertEqual(
            (self.output / proof).read_bytes(), (self.repo / proof).read_bytes()
        )
        self.assertFalse((self.output / historical_qa).exists())
        self.assertFalse((self.output / unlisted_draft).exists())

    def test_archive_substitution_cannot_change_exported_source(self) -> None:
        self.write("README.md", "$Format:%H$\n")
        self.write(".gitattributes", "README.md export-subst\n")
        self.git("add", "README.md", ".gitattributes")
        self.git("commit", "-qm", "Add substitution fixture")
        export_public_snapshot.export_snapshot(self.repo, "HEAD", self.output)
        self.assertEqual((self.output / "README.md").read_text(), "$Format:%H$\n")

    def test_destination_inside_source_repository_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            export_public_snapshot.export_snapshot(
                self.repo, "HEAD", self.repo / "public"
            )
        self.assertFalse((self.repo / "public").exists())

    def test_selected_symlink_is_refused_before_output_is_created(self) -> None:
        (self.repo / "lib/link.dart").symlink_to("../docs/private-review.md")
        self.git("add", "lib/link.dart")
        self.git("commit", "-qm", "Add selected symlink fixture")
        with self.assertRaises(ValueError):
            export_public_snapshot.export_snapshot(self.repo, "HEAD", self.output)
        self.assertFalse(self.output.exists())

    def test_missing_required_file_is_refused(self) -> None:
        self.git("rm", "LICENSE")
        self.git("commit", "-qm", "Remove required fixture")
        with self.assertRaises(ValueError):
            export_public_snapshot.export_snapshot(self.repo, "HEAD", self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
