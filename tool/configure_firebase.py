"""Generate optional native Firebase configuration for an explicitly chosen project."""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    project = os.environ.get("FIREBASE_PROJECT_ID", "").strip()
    if not project:
        print(
            "Set FIREBASE_PROJECT_ID to a Firebase project you control before running setup.",
            file=sys.stderr,
        )
        return 2

    result = subprocess.run(
        [
            "flutterfire",
            "configure",
            f"--project={project}",
            "--platforms=android,ios",
            "--android-package-name=kr.donminzzi.pebbix",
            "--ios-bundle-id=kr.donminzzi.pebbix",
            "--yes",
        ],
        check=False,
        cwd=ROOT,
    )
    if result.returncode:
        return result.returncode
    return subprocess.run(
        [sys.executable, str(ROOT / "tool/postprocess_flutterfire.py")],
        check=False,
        cwd=ROOT,
    ).returncode


if __name__ == "__main__":
    sys.exit(main())
