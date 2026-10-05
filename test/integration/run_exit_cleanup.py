"""Run two real Godot exit processes and retain their complete logs."""

import argparse
import ctypes
import json
import queue
import re
import subprocess
import threading
import time
from pathlib import Path


def close_owned_window(pid: int) -> None:
    user32 = ctypes.windll.user32
    matches = []
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

    @callback_type
    def visit(handle, _data):
        owner = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(ctypes.c_void_p(handle), ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(ctypes.c_void_p(handle)):
            matches.append(handle)
        return True

    user32.EnumWindows(visit, 0)
    if not matches:
        raise RuntimeError("The owned Godot process has no visible window")
    for handle in matches:
        if not user32.PostMessageW(ctypes.c_void_p(handle), 0x0010, 0, 0):
            raise RuntimeError("Posting WM_CLOSE to the owned Godot window failed")


def owned_engine_pid(launcher_pid: int, engine_pid: int) -> bool:
    if engine_pid == launcher_pid:
        return True
    command = ["powershell.exe", "-NoProfile", "-Command",
               f"(Get-CimInstance Win32_Process -Filter 'ProcessId = {engine_pid}').ParentProcessId"]
    parent = subprocess.check_output(command, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
    return parent.strip() == str(launcher_pid)


def run_case(engine: Path, project: Path, output: Path, mode: str) -> dict:
    log = output / f"exit-{mode}-engine.log"
    command = [str(engine), "--path", str(project), "--rendering-method",
               "gl_compatibility", "--verbose", "--log-file", str(log),
               "-s", "test/integration/test_exit_cleanup.gd", "--", f"--exit-path={mode}"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace")
    received = queue.Queue()
    lines = []

    def read_output():
        for line in process.stdout:
            received.put(line)
        received.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    deadline = time.monotonic() + 30.0
    close_sent = False
    window_pid = None
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("The owned Godot exit process exceeded 30 seconds")
            line = received.get(timeout=remaining)
            if line is None:
                break
            lines.append(line)
            if mode == "window" and "EXIT_WINDOW_READY " in line and not close_sent:
                ready = json.loads(line.split("EXIT_WINDOW_READY ", 1)[1])
                if not owned_engine_pid(process.pid, ready["pid"]):
                    raise RuntimeError("Refusing to close a window belonging to another process")
                window_pid = ready["pid"]
                close_owned_window(window_pid)
                close_sent = True
        exit_code = process.wait(timeout=5.0)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5.0)
        reader.join(timeout=1.0)
        (output / f"exit-{mode}-stdout.log").write_text("".join(lines), encoding="utf-8")
    full_log = "".join(lines) + log.read_text(encoding="utf-8", errors="replace")
    findings = [line for line in full_log.splitlines()
                if re.search(r"(?:WARNING:|ERROR:|SCRIPT ERROR:|Leaked instance:)", line)]
    markers = [line for line in lines if "EXIT_CLEANUP_RESULT " in line]
    result = json.loads(markers[-1].split("EXIT_CLEANUP_RESULT ", 1)[1]) if markers else None
    passed = exit_code == 0 and result is not None and result["failures"] == 0 and not findings
    if mode == "window":
        passed = passed and close_sent
    return {"mode": mode, "pid": process.pid, "exit_code": exit_code,
            "window_pid": window_pid,
            "real_window_close_sent": close_sent, "result": result,
            "log_findings": findings, "passed": passed}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    cases = [run_case(options.godot.resolve(), options.project.resolve(),
                      options.output.resolve(), mode) for mode in ("button", "window")]
    report = {"cases": cases, "passed": all(case["passed"] for case in cases)}
    (options.output / "exit-cleanup-report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
