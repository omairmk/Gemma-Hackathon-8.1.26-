import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


def load_server_process():
    path = ROOT / "scripts/server_process.py"
    spec = importlib.util.spec_from_file_location("server_process_os_boundary", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize(
    "diagnostic",
    [
        "route: writing to routing socket: not in table\n",
        " route:   route has not been found \r\n",
        "route: writing to routing socket: not in table\nroute: route has not been found\n",
    ],
)
def test_no_default_route_accepts_only_normalized_macos_diagnostic(diagnostic):
    module = load_server_process()
    assert module.validate_no_default_route(1, diagnostic) in module.NO_DEFAULT_ROUTE_DIAGNOSTICS


@pytest.mark.parametrize(
    ("status", "diagnostic"),
    [
        (0, "route: writing to routing socket: not in table"),
        (142, "route: writing to routing socket: not in table"),
        (1, "Operation not permitted"),
        (1, "exec failed: /sbin/route"),
        (1, "route: writing to routing socket: not in table\nOperation not permitted"),
        (1, "timeout\nroute: route has not been found"),
    ],
)
def test_no_default_route_rejects_success_timeout_permission_exec_and_mixed_errors(status, diagnostic):
    module = load_server_process()
    with pytest.raises(ValueError, match="does not prove"):
        module.validate_no_default_route(status, diagnostic)


def fake_process_runner(module, command, executable, starts):
    def run(argv, **kwargs):
        assert argv[0] in {module.PS, module.LSOF}
        if argv[0] == module.PS:
            field = argv[-1]
            if field == "command=":
                stdout = command + "\n"
            elif field == "lstart=":
                stdout = starts.pop(0) + "\n"
            else:
                raise AssertionError(argv)
        else:
            assert argv == [module.LSOF, "-nP", "-a", "-p", "123", "-d", "txt", "-F", "n"]
            stdout = f"p123\nn{executable}\n"
        return subprocess.CompletedProcess(argv, 0, stdout=stdout, stderr="")

    return run


def pinned_e4b_path() -> Path:
    manifest = json.loads((ROOT / "model_manifest.json").read_text())
    return (ROOT / manifest["models"]["e4b"]["snapshot_path"]).resolve()


def test_read_identity_binds_exact_argv_executable_and_stable_start_time(monkeypatch):
    module = load_server_process()
    model = pinned_e4b_path()
    server = ROOT / ".venv/bin/mlx_vlm.server"
    python = ROOT / ".venv/bin/python"
    command = f"{python} {server} --model {model.resolve()} --host 127.0.0.1 --port 8080"
    executable = python.resolve()
    start = "Thu Jul 31 12:34:56 2026"
    monkeypatch.setattr(module.subprocess, "run", fake_process_runner(module, command, executable, [start, start]))

    identity = module.read_identity(ROOT, model, 8080, 123)

    assert identity == {
        "pid": 123,
        "process_command": command,
        "executable_path": str(executable),
        "start_time": start,
    }


def test_read_identity_rejects_pid_reuse_during_inspection(monkeypatch):
    module = load_server_process()
    model = pinned_e4b_path()
    server = ROOT / ".venv/bin/mlx_vlm.server"
    python = ROOT / ".venv/bin/python"
    command = f"{python} {server} --model {model.resolve()} --host 127.0.0.1 --port 8080"
    starts = ["Thu Jul 31 12:34:56 2026", "Thu Jul 31 12:35:01 2026"]
    monkeypatch.setattr(module.subprocess, "run", fake_process_runner(module, command, python.resolve(), starts))

    with pytest.raises(ValueError, match="identity changed"):
        module.read_identity(ROOT, model, 8080, 123)


def test_read_identity_rejects_wrong_actual_executable(monkeypatch):
    module = load_server_process()
    model = pinned_e4b_path()
    server = ROOT / ".venv/bin/mlx_vlm.server"
    python = ROOT / ".venv/bin/python"
    command = f"{python} {server} --model {model.resolve()} --host 127.0.0.1 --port 8080"
    start = "Thu Jul 31 12:34:56 2026"
    monkeypatch.setattr(module.subprocess, "run", fake_process_runner(module, command, Path("/bin/sh"), [start]))

    with pytest.raises(ValueError, match="executable does not match"):
        module.read_identity(ROOT, model, 8080, 123)


def test_shell_boundaries_use_absolute_tools_isolation_and_prewrite_symlink_checks():
    verify = (ROOT / "scripts/verify_socket.sh").read_text()
    for tool in ("/usr/sbin/lsof", "/usr/bin/awk", "/usr/bin/sed", "/usr/bin/wc", "/usr/bin/tr"):
        assert tool in verify

    offline = (ROOT / "scripts/offline_test.sh").read_text()
    assert '"$ROOT/.venv/bin/python" -I "$ROOT/scripts/server_process.py"' in offline
    assert '"$ROOT/.venv/bin/python" -I -c "$ISOLATED_RUNNER"' in offline
    assert offline.index('assert_no_workspace_symlink "$ROUTE_LOG"') < offline.index("-setairportpower")
    assert "--classify-no-route --route-exit-status" in offline
    assert "NEW_IDENTITY_AFTER" in offline

    start = (ROOT / "scripts/start_model.sh").read_text()
    launcher = '"$ROOT/.venv/bin/mlx_vlm.server" --model'
    assert start.index('assert_no_workspace_symlink "$LOG_FILE"') < start.index(launcher)
    assert start.index('assert_no_workspace_symlink "$PID_FILE"') < start.index(launcher)
    assert '"$ROOT/.venv/bin/python" -I -' in start
    assert "/usr/bin/mktemp" in start


def test_socket_verifier_rejects_bad_pid_and_nonqualifying_port_before_lsof():
    script = ROOT / "scripts/verify_socket.sh"
    bad_pid = subprocess.run([str(script), "not-a-pid", "8080"], capture_output=True, text=True, timeout=5)
    assert bad_pid.returncode != 0
    assert "numeric" in bad_pid.stderr
    bad_port = subprocess.run([str(script), "123", "8081"], capture_output=True, text=True, timeout=5)
    assert bad_port.returncode != 0
    assert "fixed to port 8080" in bad_port.stderr
