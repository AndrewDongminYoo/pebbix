# SPDX-FileCopyrightText: 2026 kr.donminzzi
# SPDX-License-Identifier: MIT

"""Regression checks for the generated FlutterFire Xcode build phase."""

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tool import postprocess_flutterfire


class CrashlyticsScriptTest(unittest.TestCase):
    def test_flutter_build_finds_spm_checkout_outside_build_dir(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "ios").mkdir()
            project = root / "Runner.xcodeproj/project.pbxproj"
            project.parent.mkdir()
            project.write_text(postprocess_flutterfire.PROJECT.read_text())
            script_path = (
                root
                / "build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
            )
            script_path.parent.mkdir(parents=True)
            script_path.write_text("#!/bin/sh\nprintf 'found\\n'\n")
            script_path.chmod(0o755)

            with patch.object(postprocess_flutterfire, "PROJECT", project):
                postprocess_flutterfire.update_project()

            phase = re.search(
                r"\t\t[0-9A-F]{24} /\* FlutterFire: [^\n]* \*/ = \{.*?\n\t\t\};",
                project.read_text(),
                re.DOTALL,
            )
            self.assertIsNotNone(phase)
            shell_script = re.search(r"\t\t\tshellScript = (\".*?\");", phase.group())
            self.assertIsNotNone(shell_script)
            environment = os.environ | {
                "BUILD_DIR": str(root / "unrelated/Build/Products"),
                "CONFIGURATION": "Release-production",
                "FLUTTER_BUILD_DIR": "build",
                "PROJECT_DIR": str(root / "ios"),
            }
            result = subprocess.run(
                ["/bin/sh", "-c", json.loads(shell_script.group(1))],
                capture_output=True,
                check=False,
                env=environment,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "found\n")


if __name__ == "__main__":
    unittest.main()
