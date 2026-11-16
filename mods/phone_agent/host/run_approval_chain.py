#!/usr/bin/env python3
"""Host driver for the app-approval chain suite (M36).

Runs `flutter test integration_test/phone_agent_approval_chain_test.dart` in a
Loader-composited tree and performs the host actions the suite asks for. The
suite drives the real product path (tool entry -> `permission_required` ->
approval card -> `resolveApproval` -> re-observe -> revoke -> denied again);
this script only provides what a device cannot do from inside the app process:
putting an **unapproved third-party app** in the foreground.

Every host step also captures evidence (`uiautomator dump` + `screencap`) next
to the run log, so the report can point at real device state instead of only
the Flutter-side assertions.

Environment (same names as `driver.py`):
  APP_TREE    composite tree to run `flutter test` in (required)
  SERIAL      adb serial, default emulator-5554
  DRIVER_LOG  log file name inside OUT_DIR, default approval_chain.log
  OUT_DIR     where run logs / UI dumps / screenshots go
  FLUTTER_BIN flutter executable
  USE_SETTINGS_PUT `1` only on the MIUI device documented in AGENTS.md

The caller must save and restore `enabled_accessibility_services`,
`accessibility_enabled` and `stay_on_while_plugged_in` to that device's real
values; this script enables the service but never restores those settings.
"""
import os
import shlex
import shutil
import subprocess
import sys
import threading
import time

import driver

SERIAL = os.environ.get("SERIAL", "emulator-5554")
APP_TREE = os.environ["APP_TREE"]
LOG = os.path.join(driver.RUN_DIR, os.environ.get("DRIVER_LOG", "approval_chain.log"))
TEST_FILE = os.environ.get(
    "TEST_FILE", "integration_test/phone_agent_approval_chain_test.dart"
)
EVIDENCE_PREFIX = os.environ.get("EVIDENCE_PREFIX", "approval")


def evidence(name):
    """Dump the UI tree and take a screenshot for the report."""
    xml = driver.dump_ui(f"{EVIDENCE_PREFIX}-{name}")
    path = os.path.join(driver.RUN_DIR, f"{EVIDENCE_PREFIX}-{name}.png")
    try:
        with open(path, "wb") as fh:
            subprocess.run(
                ["adb", "-s", driver.SERIAL, "exec-out", "screencap", "-p"],
                stdout=fh, check=False, timeout=60,
            )
    except Exception as exc:  # evidence must never fail the run
        driver.log(f"evidence {name}: screenshot failed {exc!r}")
    texts = [t for t in (
        n.get("text") or n.get("content-desc") or "" for n in driver.nodes(xml)
    ) if t]
    driver.log(f"evidence {name}: focus={driver.foreground()[0]} texts={texts[:8]}")


def go_home():
    """Put an unapproved third-party app (the launcher) in the foreground."""
    # Cancel the enable flow's in-flight `ensure_app_foreground` first: it runs
    # on its own thread and otherwise finishes *after* HOME and pulls the app
    # back to the front (M36 r2: focus=MainActivity 3 s after go_home), which
    # makes the very next tool call observe the test app instead of launcher.
    driver.bump_navigation("approval-target-foreground")
    driver.adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(2.0)
    driver.log(f"go_home: focus={driver.foreground()[0]}")
    evidence("launcher-foreground")


MARKERS = {
    "PHONE_AGENT_APPROVAL_TARGET_FOREGROUND": go_home,
}


def main():
    open(LOG, "w", encoding="utf-8").close()
    driver.LOG = LOG
    # Host helpers resolve the device through `driver.SERIAL`.
    driver.SERIAL = SERIAL
    # `driver.scan_line` looks markers up in its own table, so register ours
    # there instead of keeping a private one.
    driver.MARKERS.update(MARKERS)
    flutter = os.environ.get("FLUTTER_BIN") or shutil.which("flutter") or "flutter.bat"
    cmd = [flutter, "test", TEST_FILE, "-d", SERIAL]
    extra = os.environ.get("TEST_ARGS")
    if extra:
        cmd += shlex.split(extra)
    driver.log("starting: " + " ".join(cmd))

    enabled = threading.Event()

    def enable():
        try:
            generation = driver.navigation_generation()
            _enable()
            # The suite may already have asked the host to put an unapproved
            # app in the foreground. A late `am start` would undo that and the
            # next tool call would observe the test app instead (M36 r4:
            # `after enable` landed 1 s after HOME).
            if driver.navigation_generation() != generation:
                driver.log("enable finished after navigation: not re-foregrounding")
            else:
                driver.adb("shell", "am", "start", "-n", driver.MAIN)
            driver.log(f"after enable: focus={driver.foreground()}")
            enabled.set()
        except Exception as exc:
            driver.log(f"enable failed: {exc!r}")

    def _enable():
        if os.environ.get("USE_SETTINGS_PUT") == "1":
            component = (
                "com.psyche.kelivo.phoneagent/"
                "com.kelivo.phoneagent.PhoneAgentService"
            )
            driver.adb("shell", "settings", "put", "secure",
                       "enabled_accessibility_services", component)
            driver.adb("shell", "settings", "put", "secure",
                       "accessibility_enabled", "1")
            time.sleep(2)
            driver.log(f"enabled via settings put secure; bound={driver.bound()}")
        else:
            driver.enable_service()
        driver.adb("shell", "svc", "power", "stayon", "true")
        driver.adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        time.sleep(1)
        driver.adb("shell", "wm", "dismiss-keyguard")
        time.sleep(1)
        driver.adb("shell", "cmd", "statusbar", "collapse")
        time.sleep(1)

    threading.Thread(target=driver.action_worker, daemon=True).start()

    proc = subprocess.Popen(
        cmd, cwd=APP_TREE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    started = time.time()
    try:
        for line in proc.stdout:
            with open(LOG, "a", encoding="utf-8") as fh:
                fh.write(line)
            if line.strip() == "PHONE_AGENT_WAITING_FOR_SERVICE" and not enabled.is_set():
                driver.log("marker PHONE_AGENT_WAITING_FOR_SERVICE")
                threading.Thread(target=enable, daemon=True).start()
            if "PHONE_AGENT_" in line:
                driver.scan_line(line, "stdout")
            if "All tests passed" in line or "Some tests failed" in line:
                driver.log("suite finished")
    finally:
        proc.wait(timeout=240)
        driver.log(
            f"flutter test exit={proc.returncode} elapsed={int(time.time() - started)}s"
        )
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
