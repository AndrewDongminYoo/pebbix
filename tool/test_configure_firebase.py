"""Check that optional Firebase setup never selects the publisher implicitly."""

import io
import subprocess
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch

from tool import configure_firebase


class ConfigureFirebaseTest(unittest.TestCase):
    def test_missing_project_does_not_invoke_external_commands(self) -> None:
        for project in ("", "   "):
            with self.subTest(project=project):
                with (
                    patch.dict("os.environ", {"FIREBASE_PROJECT_ID": project}),
                    patch.object(configure_firebase.subprocess, "run") as run,
                    redirect_stderr(io.StringIO()) as errors,
                ):
                    self.assertEqual(configure_firebase.main(), 2)
                run.assert_not_called()
                self.assertIn("FIREBASE_PROJECT_ID", errors.getvalue())

    def test_explicit_project_is_forwarded_before_postprocessing(self) -> None:
        with (
            patch.dict("os.environ", {"FIREBASE_PROJECT_ID": "contributor-project"}),
            patch.object(
                configure_firebase.subprocess,
                "run",
                return_value=subprocess.CompletedProcess([], 0),
            ) as run,
        ):
            self.assertEqual(configure_firebase.main(), 0)
        self.assertEqual(run.call_count, 2)
        command = run.call_args_list[0].args[0]
        self.assertEqual(command[:2], ["flutterfire", "configure"])
        self.assertIn("--project=contributor-project", command)
        self.assertEqual(run.call_args_list[0].kwargs["cwd"], configure_firebase.ROOT)
        self.assertEqual(
            run.call_args_list[1].args[0][1],
            str(configure_firebase.ROOT / "tool/postprocess_flutterfire.py"),
        )

    def test_flutterfire_failure_does_not_run_postprocessing(self) -> None:
        with (
            patch.dict("os.environ", {"FIREBASE_PROJECT_ID": "contributor-project"}),
            patch.object(
                configure_firebase.subprocess,
                "run",
                return_value=subprocess.CompletedProcess([], 17),
            ) as run,
        ):
            self.assertEqual(configure_firebase.main(), 17)
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
