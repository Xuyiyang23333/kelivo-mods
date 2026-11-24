#!/usr/bin/env python3
"""Run the official Phone Agent integration test with host service enabling.

The official suite (`phone_agent_test.dart`) only needs the accessibility
service enabled; it drives the rest itself. This wrapper reuses the exception
suite driver's host helpers (system-UI enabling, foreground confirmation) and
answers its single `PHONE_AGENT_WAITING_FOR_SERVICE` marker.

Environment: same as `driver.py`, plus
  TEST_FILE        suite to run, default integration_test/phone_agent_test.dart
  USE_SETTINGS_PUT `1` to enable the service with `settings put secure`
                   only on physical devices that permit it (e.g. MIUI). It is
                   never the default and never used on the emulator, where
                   enabling must go through the system UI.

The caller must save and restore `enabled_accessibility_services`,
`accessibility_enabled` and `stay_on_while_plugged_in` to that device's real
values; this script sets `svc power stayon true` for the run and leaves the
restore to the operator.
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
LOG = os.path.join(driver.RUN_DIR, os.environ.get("DRIVER_LOG", "official.log"))
TEST_FILE = os.environ.get("TEST_FILE", "integration_test/phone_agent_test.dart")


def main():
    driver.LOG = LOG
    # Host helpers resolve the device through `driver.SERIAL`, so the override
    # must be applied there, not only in this module.
    driver.SERIAL = SERIAL
    open(LOG, "w", encoding="utf-8").close()
    flutter = (
        os.environ.get("FLUTTER_BIN") or shutil.which("flutter") or "flutter.bat"
    )
    cmd = [flutter, "test", TEST_FILE, "-d", SERIAL]
    extra = os.environ.get("TEST_ARGS")
    if extra:
        cmd += shlex.split(extra)
    driver.log("starting: " + " ".join(cmd))

    done = threading.Event()

    def enable():
        try:
            _enable()
        except Exception as exc:  # M36: never let the enable thread die silently
            driver.log(f"enable failed: {exc!r}")

    def _enable():
        # The suite waits ~20 s (plus a 300 s poll) for the host to enable the
        # service. MIUI allows `settings put secure` under this mission's
        # documented exception; API35 must go through the system UI.
        if os.environ.get("USE_SETTINGS_PUT") == "1":
            component = (
                "com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.PhoneAgentService"
            )
            driver.adb("shell", "settings", "put", "secure",
                       "enabled_accessibility_services", component)
            driver.adb("shell", "settings", "put", "secure",
                       "accessibility_enabled", "1")
            time.sleep(2)
            driver.log(f"enabled via settings put secure; bound={driver.bound()}")
        else:
            driver.enable_service()
        # Keep the panel awake for the whole run: MIUI slept mid-suite and the
        # product correctly returned `device_locked`. `stay_on_while_plugged_in`
        # is restored by the caller after the run.
        driver.adb("shell", "svc", "power", "stayon", "true")
        driver.adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        time.sleep(1)
        driver.adb("shell", "wm", "dismiss-keyguard")
        time.sleep(1)
        driver.adb("shell", "cmd", "statusbar", "collapse")
        time.sleep(1)
        driver.adb("shell", "am", "start", "-n", driver.MAIN)
        driver.log(f"after enable: focus={driver.foreground()}")
        done.set()

    threading.Thread(target=driver.action_worker, daemon=True).start()

    # M36: the first "enable Phone Agent" in the Mods page shows the one-time
    # privacy notice and then requests POST_NOTIFICATIONS. The host dismisses
    # that dialog by **denying** it, which keeps the permission at
    # `granted=false` as the exception suite requires (its permission-window
    # case needs an un-granted POST_NOTIFICATIONS). Denial is allowed by the
    # documented host contract; granting is not, and neither is `pm revoke`.
    #
    # Causal note (R1): the r10 log shows the Mods assertion passing ~10 s
    # *before* this denial, so this thread is **not** proven to be what
    # unblocks `writeSelection`; that gating rests on the product code path
    # (`await _ensureNotificationPermission()` inside `ensureAcknowledged`).
    # What the log does prove is that the dialog appeared and was denied.
    #
    # Scope guard: this is a 240 s daemon loop that only acts when
    # `permissioncontroller` is the focused window — otherwise it idles. It can
    # therefore hit an unrelated permission dialog; run1 hit exactly once and
    # did not interfere.
    def dismiss_notification_prompt():
        seen = 0
        for _ in range(240):
            time.sleep(1.0)
            focus, _ = driver.foreground()
            if not focus or "permissioncontroller" not in focus:
                continue
            seen += 1
            xml = driver.dump_ui(f"notif-prompt-{seen}")
            deny = driver.find(xml, text="Don't allow", button_only=True) or \
                driver.find(xml, text="Don’t allow", button_only=True) or \
                driver.find(xml, text="不允许", button_only=True)
            if deny is not None:
                driver.tap_node(deny)
                driver.log("dismissed POST_NOTIFICATIONS prompt (denied)")
                driver.ensure_app_foreground()
            else:
                driver.adb("shell", "input", "keyevent", "KEYCODE_BACK")
                driver.log("POST_NOTIFICATIONS prompt: no deny button, sent BACK")

    threading.Thread(target=dismiss_notification_prompt, daemon=True).start()

    proc = subprocess.Popen(
        cmd, cwd=APP_TREE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    started = time.time()
    try:
        for line in proc.stdout:
            with open(LOG, "a", encoding="utf-8") as fh:
                fh.write(line)
            if line.strip() == "PHONE_AGENT_WAITING_FOR_SERVICE" and not done.is_set():
                driver.log("marker PHONE_AGENT_WAITING_FOR_SERVICE")
                threading.Thread(target=enable, daemon=True).start()
            if "All tests passed" in line or "Some tests failed" in line:
                driver.log("suite finished")
    finally:
        proc.wait(timeout=180)
        driver.log(
            f"flutter test exit={proc.returncode} elapsed={int(time.time() - started)}s"
        )
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
