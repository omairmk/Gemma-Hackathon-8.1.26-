#!/usr/bin/python3

"""Run one host command with a bounded wall-clock timeout.

The child starts in its own process group so timeout or host termination cleans
up the direct child and every same-group descendant before this helper exits.
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time


TIMEOUT_EXIT_STATUS = 124
CLEANUP_FAILURE_STATUS = 125
TERMINATION_GRACE_SECONDS = 2


class TerminationRequested(Exception):
    def __init__(self, signal_number: int) -> None:
        super().__init__(f"received host signal {signal_number}")
        self.signal_number = signal_number


def terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    process_group_id = process.pid
    try:
        os.killpg(process_group_id, signal.SIGTERM)
    except ProcessLookupError:
        try:
            process.wait(timeout=TERMINATION_GRACE_SECONDS)
        except subprocess.TimeoutExpired as error:
            try:
                process.kill()
            except OSError as kill_error:
                raise RuntimeError(
                    f"could not kill child outside its process group: {kill_error}"
                ) from kill_error
            process.wait(timeout=TERMINATION_GRACE_SECONDS)
            raise RuntimeError(
                "direct child escaped its dedicated process group"
            ) from error
        return
    except OSError as error:
        raise RuntimeError(
            f"could not signal dedicated process group with SIGTERM: {error}"
        ) from error

    # Do not reap the direct child during the grace period. Its unreaped PID
    # prevents process-group ID reuse while same-group descendants wind down.
    # A child exiting early therefore cannot make us skip cleanup of a
    # descendant that ignored SIGTERM.
    grace_deadline = time.monotonic() + TERMINATION_GRACE_SECONDS
    while True:
        remaining_grace = grace_deadline - time.monotonic()
        if remaining_grace <= 0:
            break
        time.sleep(min(0.05, remaining_grace))

    group_kill_error: OSError | None = None
    try:
        os.killpg(process_group_id, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError as error:
        group_kill_error = error
    try:
        process.wait(timeout=TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired as error:
        # The Popen object still owns an unreaped direct child, so this signal
        # cannot target a recycled PID even if the child escaped its group.
        try:
            process.kill()
        except OSError as kill_error:
            raise RuntimeError(
                f"could not kill direct child after group SIGKILL: {kill_error}"
            ) from kill_error
        try:
            process.wait(timeout=TERMINATION_GRACE_SECONDS)
        except subprocess.TimeoutExpired as final_error:
            raise RuntimeError(
                "could not reap timed-out direct child after SIGKILL"
            ) from final_error
        raise RuntimeError(
            "timed-out direct child escaped process-group SIGKILL"
        ) from error
    if group_kill_error is not None:
        try:
            os.killpg(process_group_id, 0)
        except ProcessLookupError:
            return
        except OSError as verification_error:
            raise RuntimeError(
                "could not verify process-group exit after SIGKILL error: "
                f"{verification_error}"
            ) from group_kill_error
        raise RuntimeError(
            "dedicated process group survived a failed SIGKILL: "
            f"{group_kill_error}"
        ) from group_kill_error


def terminate_process_group_without_interruption(
    process: subprocess.Popen[bytes],
) -> None:
    cleanup_signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    previous_handlers = {
        signal_number: signal.signal(signal_number, signal.SIG_IGN)
        for signal_number in cleanup_signals
    }
    try:
        terminate_process_group(process)
    finally:
        for signal_number, previous_handler in previous_handlers.items():
            signal.signal(signal_number, previous_handler)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a command in a new process group with a hard timeout."
    )
    parser.add_argument("--timeout-seconds", type=int)
    parser.add_argument("--probe-pid", type=int)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if arguments.probe_pid is not None:
        if arguments.probe_pid < 1:
            parser.error("--probe-pid must be a positive process ID")
        if arguments.timeout_seconds is not None or arguments.command:
            parser.error("--probe-pid cannot be combined with a command or timeout")
        return arguments
    if arguments.timeout_seconds is None or arguments.timeout_seconds < 1:
        parser.error("--timeout-seconds must be at least 1")
    if arguments.command[:1] == ["--"]:
        arguments.command = arguments.command[1:]
    if not arguments.command:
        parser.error("a command is required after --")
    return arguments


def probe_pid(pid: int) -> int:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        print("__LIVENESS__=absent")
        return 0
    except PermissionError:
        print("__LIVENESS__=unknown")
        return 70
    except OSError as error:
        print(f"__LIVENESS__=unknown errno={error.errno}")
        return 70
    print("__LIVENESS__=alive")
    return 0


def main() -> int:
    arguments = parse_arguments()
    if arguments.probe_pid is not None:
        return probe_pid(arguments.probe_pid)
    handled_host_signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    termination_state: dict[str, object | None] = {
        "process": None,
        "pending_signal": None,
    }

    def request_termination(signal_number: int, _frame: object) -> None:
        if termination_state["process"] is None:
            termination_state["pending_signal"] = signal_number
            return
        raise TerminationRequested(signal_number)

    previous_handlers = {
        signal_number: signal.signal(signal_number, request_termination)
        for signal_number in handled_host_signals
    }
    process: subprocess.Popen[bytes] | None = None
    try:
        try:
            process = subprocess.Popen(arguments.command, start_new_session=True)
        except FileNotFoundError as error:
            print(
                f"timeout helper could not execute command: {error}",
                file=sys.stderr,
            )
            return 127
        termination_state["process"] = process
        pending_signal = termination_state["pending_signal"]
        if isinstance(pending_signal, int):
            raise TerminationRequested(pending_signal)

        try:
            return process.wait(timeout=arguments.timeout_seconds)
        except subprocess.TimeoutExpired:
            print(
                f"command exceeded {arguments.timeout_seconds}s hard timeout",
                file=sys.stderr,
            )
            try:
                terminate_process_group_without_interruption(process)
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                print(f"timeout cleanup failed: {error}", file=sys.stderr)
                return CLEANUP_FAILURE_STATUS
            return TIMEOUT_EXIT_STATUS
        except KeyboardInterrupt:
            try:
                terminate_process_group_without_interruption(process)
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                print(f"interrupt cleanup failed: {error}", file=sys.stderr)
                return CLEANUP_FAILURE_STATUS
            return 130
    except TerminationRequested as request:
        if process is None:
            return 128 + request.signal_number
        try:
            terminate_process_group_without_interruption(process)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            print(f"host-signal cleanup failed: {error}", file=sys.stderr)
            return CLEANUP_FAILURE_STATUS
        return 128 + request.signal_number
    finally:
        for signal_number, previous_handler in previous_handlers.items():
            signal.signal(signal_number, previous_handler)


if __name__ == "__main__":
    raise SystemExit(main())
