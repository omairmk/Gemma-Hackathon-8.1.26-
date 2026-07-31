"""Exact argv validation for the workspace-local MLX-VLM server process."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path


PS = "/bin/ps"
LSOF = "/usr/sbin/lsof"
NO_DEFAULT_ROUTE_DIAGNOSTICS = {
    "route: writing to routing socket: not in table",
    "route: route has not been found",
    "route: writing to routing socket: not in table\nroute: route has not been found",
}


def _validated_tokens(root: Path, model_path: Path, port: int, command: str) -> tuple[list[str], int]:
    """Return the parsed command only after validating the complete launch argv."""
    root = root.resolve()
    model_path = model_path.resolve()
    server = str(root / ".venv/bin/mlx_vlm.server")
    try:
        tokens = shlex.split(command)
    except ValueError as error:
        raise ValueError("server process command is not parseable") from error
    positions = [index for index, token in enumerate(tokens) if token == server]
    if len(positions) != 1 or positions[0] not in {0, 1}:
        raise ValueError("live PID does not execute the exact workspace mlx_vlm.server")
    server_index = positions[0]
    if server_index == 1:
        interpreters = {
            str(root / ".venv/bin/python"),
            str(root / ".venv/bin/python3"),
            str(root / ".venv/bin/python3.12"),
            str((root / ".venv/bin/python").resolve()),
            str((root / ".venv/bin/python3").resolve()),
            str((root / ".venv/bin/python3.12").resolve()),
        }
        if tokens[0] not in interpreters:
            raise ValueError("workspace server is not launched by its exact workspace Python")
    arguments = tokens[server_index + 1:]
    if len(arguments) != 6:
        raise ValueError("live server contains unexpected or missing arguments")

    def exact_flag(flag: str) -> str:
        if arguments.count(flag) != 1:
            raise ValueError(f"live server must contain exactly one {flag}")
        index = arguments.index(flag)
        if index + 1 >= len(arguments) or arguments[index + 1].startswith("--"):
            raise ValueError(f"live server has no value for {flag}")
        return arguments[index + 1]

    if exact_flag("--model") != str(model_path):
        raise ValueError("live server model path does not match the pinned snapshot")
    if exact_flag("--host") != "127.0.0.1":
        raise ValueError("live server host is not exact IPv4 loopback")
    if exact_flag("--port") != str(port):
        raise ValueError("live server port does not match the qualifying port")
    return tokens, server_index


def validate_command(root: Path, model_path: Path, port: int, command: str) -> None:
    _validated_tokens(root, model_path, port, command)


def _ps_value(pid: int, field: str) -> str:
    if field not in {"command", "lstart"}:
        raise ValueError("unsupported process field")
    value = subprocess.run(
        [PS, "-ww", "-p", str(pid), "-o", f"{field}="],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout.strip()
    if not value:
        raise ValueError(f"server PID has no live process {field}")
    return value


def _expected_executable(root: Path, tokens: list[str], server_index: int) -> Path:
    if server_index == 1:
        executable = Path(tokens[0])
    else:
        server = root / ".venv/bin/mlx_vlm.server"
        try:
            first_line = server.open("r", encoding="utf-8").readline().rstrip("\r\n")
        except (OSError, UnicodeError) as error:
            raise ValueError("workspace server launcher shebang cannot be read") from error
        if not first_line.startswith("#!"):
            raise ValueError("workspace server launcher lacks an interpreter shebang")
        try:
            shebang = shlex.split(first_line[2:].strip())
        except ValueError as error:
            raise ValueError("workspace server launcher shebang is not parseable") from error
        if len(shebang) != 1:
            raise ValueError("workspace server launcher must use one exact interpreter")
        executable = Path(shebang[0])
    try:
        resolved = executable.resolve(strict=True)
    except OSError as error:
        raise ValueError("workspace server interpreter cannot be resolved") from error
    if not resolved.is_file():
        raise ValueError("workspace server interpreter is not a file")
    return resolved


def _actual_executable(pid: int, expected: Path) -> str:
    output = subprocess.run(
        [LSOF, "-nP", "-a", "-p", str(pid), "-d", "txt", "-F", "n"],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout
    observed = [line[1:] for line in output.splitlines() if line.startswith("n/")]
    for candidate in observed:
        try:
            if os.path.samefile(candidate, expected):
                return str(Path(candidate).resolve(strict=True))
        except OSError:
            continue
    raise ValueError("live PID executable does not match the resolved workspace Python")


def read_identity(root: Path, model_path: Path, port: int, pid: int) -> dict:
    """Validate and return a stable, JSON-safe identity for a live server PID.

    The start time is read on both sides of command/executable inspection to
    reject a PID that exited and was reused during validation.
    """
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1:
        raise ValueError("server PID must be an integer greater than 1")
    root = root.resolve()
    model_path = model_path.resolve()
    start_before = " ".join(_ps_value(pid, "lstart").split())
    if not re.fullmatch(
        r"(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) "
        r"[ 0-9]?\d \d{2}:\d{2}:\d{2} \d{4}",
        start_before,
    ):
        raise ValueError("server PID start time is not a recognized macOS ps timestamp")
    command = _ps_value(pid, "command")
    tokens, server_index = _validated_tokens(root, model_path, port, command)
    expected = _expected_executable(root, tokens, server_index)
    executable = _actual_executable(pid, expected)
    start_after = " ".join(_ps_value(pid, "lstart").split())
    if start_after != start_before:
        raise ValueError("server PID identity changed during validation")
    return {
        "pid": pid,
        "process_command": command,
        "executable_path": executable,
        "start_time": start_before,
    }


def read_and_validate(root: Path, model_path: Path, port: int, pid: int) -> str:
    """Backward-compatible command-only view of the stronger identity proof."""
    return read_identity(root, model_path, port, pid)["process_command"]


def normalize_route_diagnostic(output: str) -> str:
    lines = []
    for raw_line in output.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        normalized = " ".join(raw_line.split())
        if normalized:
            lines.append(normalized)
    return "\n".join(lines)


def validate_no_default_route(exit_status: int, output: str) -> str:
    """Accept only the exact macOS route(8) no-default-route result."""
    normalized = normalize_route_diagnostic(output)
    if exit_status != 1 or normalized not in NO_DEFAULT_ROUTE_DIAGNOSTICS:
        raise ValueError("route result does not prove that the default route is absent")
    return normalized


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int)
    parser.add_argument("--model")
    parser.add_argument("--port", type=int, default=8080, choices=(8080,))
    parser.add_argument("--identity-json", action="store_true")
    parser.add_argument("--classify-no-route", action="store_true")
    parser.add_argument("--route-exit-status", type=int)
    args = parser.parse_args()
    if args.classify_no_route:
        if args.route_exit_status is None or args.pid is not None or args.model is not None or args.identity_json:
            parser.error("route classification requires only --classify-no-route and --route-exit-status")
        try:
            print(validate_no_default_route(args.route_exit_status, sys.stdin.read()))
        except ValueError as error:
            raise SystemExit(str(error)) from error
        return
    if args.pid is None or args.model is None or args.route_exit_status is not None:
        parser.error("process validation requires --pid and --model")
    root = Path(__file__).resolve().parents[1]
    model = Path(args.model).resolve()
    if root not in model.parents:
        raise SystemExit("server model path must remain inside the workspace")
    try:
        identity = read_identity(root, model, args.port, args.pid)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
    if args.identity_json:
        print(json.dumps(identity, sort_keys=True))
    else:
        print(identity["process_command"])


if __name__ == "__main__":
    main()
