"""Export a selected committed source snapshot without development history."""

import argparse
import fnmatch
import subprocess
from pathlib import Path, PurePosixPath

MANIFEST = "tool/public_snapshot_paths.txt"


def export_snapshot(repository: Path, revision: str, output: Path) -> str:
    """Create a public review candidate from an exact committed revision."""
    repository = repository.resolve()
    actual_root = Path(
        subprocess.check_output(
            ["git", "-C", str(repository), "rev-parse", "--show-toplevel"], text=True
        ).strip()
    ).resolve()
    if repository != actual_root:
        raise ValueError("The source must be an exact Git repository root")
    if output.exists() or output.is_symlink():
        raise FileExistsError(output)
    output = output.resolve()
    if output == repository or repository in output.parents:
        raise ValueError(
            "The snapshot destination must be outside the source repository"
        )
    commit = subprocess.check_output(
        [
            "git",
            "-C",
            str(repository),
            "rev-parse",
            "--verify",
            "--end-of-options",
            f"{revision}^{{commit}}",
        ],
        text=True,
    ).strip()
    manifest = subprocess.check_output(
        ["git", "-C", str(repository), "show", f"{commit}:{MANIFEST}"], text=True
    )
    patterns = [
        line.strip()
        for line in manifest.splitlines()
        if line.strip() and not line.startswith("#")
    ]
    tree = subprocess.check_output(
        ["git", "-C", str(repository), "ls-tree", "-rz", "--full-tree", commit]
    )
    selected = []
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        metadata, raw_name = entry.split(b"\t", 1)
        name = raw_name.decode("utf-8")
        if not any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns):
            continue
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or ".git" in relative.parts:
            raise ValueError(f"Unsafe selected path: {name}")
        if metadata.split()[0] not in (b"100644", b"100755"):
            raise ValueError(f"Selected paths must be regular files: {name}")
        selected.append((name, metadata.split()[0]))
    if not {"LICENSE", "README.md"}.issubset(name for name, _ in selected):
        raise ValueError("The selected snapshot must include LICENSE and README.md")

    output.mkdir(parents=True)
    for name, mode in selected:
        # Read blobs directly: git-archive attributes can substitute committed bytes.
        content = subprocess.check_output(
            ["git", "-C", str(repository), "cat-file", "blob", f"{commit}:{name}"]
        )
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        target.chmod(0o755 if mode == b"100755" else 0o644)
    return commit


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--revision", default="HEAD")
    arguments = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    commit = export_snapshot(repository, arguments.revision, arguments.output)
    print(f"Exported committed snapshot {commit} to {arguments.output.resolve()}")


if __name__ == "__main__":
    main()
