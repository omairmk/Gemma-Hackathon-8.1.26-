#!/usr/bin/python3

"""Regression tests for the fail-closed host timeout helper."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


HELPER = Path(__file__).with_name("RunWithTimeout.py")


def process_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


class RunWithTimeoutTests(unittest.TestCase):
    def test_successful_command_returns_its_status(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "--timeout-seconds",
                "2",
                "--",
                "/usr/bin/true",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_timeout_kills_same_group_descendant_that_ignores_sigterm(self) -> None:
        grandchild_source = (
            "import os,signal,sys,time;"
            "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
            "open(sys.argv[1],'w').write(str(os.getpid()));"
            "time.sleep(30)"
        )
        direct_child_source = (
            "import subprocess,sys,time;"
            "subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]]);"
            "time.sleep(30)"
        )
        descendant_pid = 0
        with tempfile.TemporaryDirectory(prefix="gi-timeout-regression-") as temporary:
            pid_path = Path(temporary) / "descendant.pid"
            try:
                result = subprocess.run(
                    [
                        sys.executable,
                        str(HELPER),
                        "--timeout-seconds",
                        "1",
                        "--",
                        sys.executable,
                        "-c",
                        direct_child_source,
                        grandchild_source,
                        str(pid_path),
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                self.assertEqual(result.returncode, 124, result.stderr)
                self.assertIn("command exceeded 1s hard timeout", result.stderr)
                self.assertTrue(pid_path.is_file(), result.stderr)
                descendant_pid = int(pid_path.read_text(encoding="utf-8"))
                disappearance_deadline = time.monotonic() + 3
                while process_exists(descendant_pid):
                    if time.monotonic() >= disappearance_deadline:
                        self.fail(
                            "same-group descendant survived timeout cleanup"
                        )
                    time.sleep(0.05)
            finally:
                if descendant_pid and process_exists(descendant_pid):
                    os.kill(descendant_pid, signal.SIGKILL)

    def test_sigint_during_popen_assignment_cleans_child_session(self) -> None:
        helper_spec = importlib.util.spec_from_file_location(
            "gi_run_with_timeout_assignment_test",
            HELPER,
        )
        self.assertIsNotNone(helper_spec)
        self.assertIsNotNone(helper_spec.loader)
        helper_module = importlib.util.module_from_spec(helper_spec)
        helper_spec.loader.exec_module(helper_module)

        child_pid = 0
        spawned_process: subprocess.Popen[bytes] | None = None
        original_argv = sys.argv
        real_popen = helper_module.subprocess.Popen
        with tempfile.TemporaryDirectory(prefix="gi-sigint-window-") as temporary:
            pid_path = Path(temporary) / "child.pid"
            child_source = (
                "import os,sys,time;"
                "open(sys.argv[1],'w').write(str(os.getpid()));"
                "time.sleep(30)"
            )

            def interrupt_before_assignment(*args: object, **kwargs: object):
                nonlocal spawned_process
                spawned_process = real_popen(*args, **kwargs)
                startup_deadline = time.monotonic() + 3
                while not pid_path.is_file():
                    if spawned_process.poll() is not None:
                        self.fail("child exited before SIGINT assignment test")
                    if time.monotonic() >= startup_deadline:
                        self.fail("child did not start before SIGINT assignment test")
                    time.sleep(0.05)
                os.kill(os.getpid(), signal.SIGINT)
                return spawned_process

            try:
                helper_module.subprocess.Popen = interrupt_before_assignment
                sys.argv = [
                    str(HELPER),
                    "--timeout-seconds",
                    "30",
                    "--",
                    sys.executable,
                    "-c",
                    child_source,
                    str(pid_path),
                ]
                result = helper_module.main()
                self.assertEqual(result, 130)
                self.assertTrue(pid_path.is_file())
                child_pid = int(pid_path.read_text(encoding="utf-8"))
                disappearance_deadline = time.monotonic() + 3
                while process_exists(child_pid):
                    if time.monotonic() >= disappearance_deadline:
                        self.fail("child survived SIGINT assignment-window cleanup")
                    time.sleep(0.05)
            finally:
                helper_module.subprocess.Popen = real_popen
                sys.argv = original_argv
                if spawned_process is not None and spawned_process.poll() is None:
                    spawned_process.kill()
                    spawned_process.wait(timeout=3)
                if child_pid and process_exists(child_pid):
                    os.kill(child_pid, signal.SIGKILL)

    def test_sigterm_to_helper_cleans_up_child_session(self) -> None:
        grandchild_source = (
            "import os,signal,sys,time;"
            "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
            "open(sys.argv[1],'w').write(str(os.getpid()));"
            "time.sleep(30)"
        )
        direct_child_source = (
            "import subprocess,sys,time;"
            "subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]]);"
            "time.sleep(30)"
        )
        descendant_pid = 0
        helper_process: subprocess.Popen[str] | None = None
        with tempfile.TemporaryDirectory(prefix="gi-sigterm-regression-") as temporary:
            pid_path = Path(temporary) / "descendant.pid"
            try:
                helper_process = subprocess.Popen(
                    [
                        sys.executable,
                        str(HELPER),
                        "--timeout-seconds",
                        "30",
                        "--",
                        sys.executable,
                        "-c",
                        direct_child_source,
                        grandchild_source,
                        str(pid_path),
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                startup_deadline = time.monotonic() + 3
                while not pid_path.is_file():
                    if helper_process.poll() is not None:
                        self.fail("helper exited before the child session started")
                    if time.monotonic() >= startup_deadline:
                        self.fail("child session did not start before SIGTERM test")
                    time.sleep(0.05)
                descendant_pid = int(pid_path.read_text(encoding="utf-8"))
                helper_process.send_signal(signal.SIGTERM)
                _, stderr = helper_process.communicate(timeout=10)
                self.assertEqual(helper_process.returncode, 143, stderr)
                disappearance_deadline = time.monotonic() + 3
                while process_exists(descendant_pid):
                    if time.monotonic() >= disappearance_deadline:
                        self.fail(
                            "child-session descendant survived helper SIGTERM"
                        )
                    time.sleep(0.05)
            finally:
                if helper_process is not None and helper_process.poll() is None:
                    helper_process.kill()
                    helper_process.wait(timeout=3)
                if descendant_pid and process_exists(descendant_pid):
                    os.kill(descendant_pid, signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
