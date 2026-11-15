#!/usr/bin/env python3
"""Host driver for the Phone Agent exception suite (M30).

Runs `flutter test integration_test/phone_agent_exception_test.dart -d <serial>`
inside a Loader-composited tree and performs the host/CU actions the suite asks
for, one marker at a time. Dispatch is driven **only** by the flutter test
stdout; `adb logcat` is tailed solely to keep a device-side log next to the run
log.

This is a **host test script, not product code**. It lives in the private repo
so the green rounds can be reproduced; it is not referenced by `mod.json`, not
copied into the composite tree, and it must never gain the ability to grant
accessibility permission by bypassing the system UI (the MIUI exception is
documented in AGENTS.md and is opt-in via `USE_SETTINGS_PUT=1` in
`run_official.py`).

Environment:
  APP_TREE     composite tree to run `flutter test` in (required)
  SERIAL       adb serial, default emulator-5554
  DRIVER_LOG   run log file name inside OUT_DIR, default run.log
  OUT_DIR      where run logs and UI dumps go, default ./_runs beside the script
  FLUTTER_BIN  flutter executable, default looked up on PATH
  TEST_ARGS    extra `flutter test` args (quoted; needed for regex names)

Usage:
  APP_TREE=.../build/worktrees/<hash> python3 driver.py
"""
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time

SERIAL = os.environ.get("SERIAL", "emulator-5554")
APP_TREE = os.environ["APP_TREE"]
APP = "com.psyche.kelivo.phoneagent"
MAIN = f"{APP}/com.psyche.kelivo.MainActivity"
FIXTURE = f"{APP}/com.kelivo.phoneagent.SecureWindowFixtureActivity"
SECURE_FIXTURE = (
    "com.kelivo.phoneagent.securefixture/"
    "com.kelivo.phoneagent.securefixture.SecureFixtureActivity"
)

RUN_DIR = os.path.abspath(
    os.environ.get(
        "OUT_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_runs")
    )
)
os.makedirs(RUN_DIR, exist_ok=True)
LOG = os.path.join(RUN_DIR, os.environ.get("DRIVER_LOG", "run.log"))

_log_lock = threading.Lock()


def log(msg):
    line = f"[driver {time.strftime('%H:%M:%S')}] {msg}"
    with _log_lock:
        print(line, flush=True)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")


def adb(*args, timeout=60):
    env = dict(os.environ)
    env["MSYS_NO_PATHCONV"] = "1"
    return subprocess.run(
        ["adb", "-s", SERIAL, *args], capture_output=True, text=True,
        timeout=timeout, env=env,
    ).stdout


def dump_ui(name="ui"):
    for _ in range(4):
        out = adb("shell", "uiautomator", "dump", "/sdcard/ui.xml", timeout=45)
        if "dumped to" in out:
            local = os.path.join(RUN_DIR, f"{name}.xml")
            adb("pull", "/sdcard/ui.xml", local, timeout=45)
            try:
                with open(local, encoding="utf-8") as fh:
                    return fh.read()
            except OSError:
                pass
        time.sleep(1)
    return ""


NODE_RE = re.compile(r"<node ([^>]*?)/?>")


def nodes(xml):
    out = []
    for m in NODE_RE.finditer(xml):
        attrs = dict(re.findall(r'([\w-]+)="([^"]*)"', m.group(1)))
        b = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", attrs.get("bounds", ""))
        if not b:
            continue
        x1, y1, x2, y2 = (int(v) for v in b.groups())
        attrs["cx"] = (x1 + x2) // 2
        attrs["cy"] = (y1 + y2) // 2
        out.append(attrs)
    return out


def find(xml, text=None, rid=None, cls=None, button_only=False):
    for n in nodes(xml):
        if text is not None:
            hay = " ".join([n.get("text", ""), n.get("content-desc", "")])
            if text not in hay:
                continue
        if rid is not None and rid not in n.get("resource-id", ""):
            continue
        if cls is not None and cls not in n.get("class", ""):
            continue
        if button_only and not n.get("class", "").endswith("Button"):
            continue
        return n
    return None


def tap(x, y):
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(0.9)


def tap_node(n):
    tap(n["cx"], n["cy"])


def foreground():
    out = adb("shell", "dumpsys", "window")
    focus = re.search(r"mCurrentFocus=Window\{\S+ \S+ ([^}\s]+)", out)
    app = re.search(r"mFocusedApp=ActivityRecord\{\S+ \S+ ([^}\s]+)", out)
    return (focus.group(1) if focus else None, app.group(1) if app else None)


def top_activity():
    out = adb("shell", "dumpsys", "activity", "activities")
    m = re.search(r"topResumedActivity=ActivityRecord\{\S+ \S+ ([^}\s]+)", out)
    return m.group(1) if m else None


def ensure_app_foreground(expect_activity="com.psyche.kelivo.MainActivity"):
    """Make the *test harness activity* the resumed activity.

    Package equality is not enough: the same APK hosts
    SecureWindowFixtureActivity, so `am start MainActivity` on a task whose top
    activity is the fixture brings the task forward and leaves the fixture on
    top. Round 3 failed exactly that way — the tree was readable, the package
    matched, and PHONE_AGENT_TAP_TARGET was missing.
    """
    _shade_stop.set()
    stable = 0
    for _ in range(18):
        top = top_activity() or ""
        focus, _ = foreground()
        focused_harness = bool(focus) and expect_activity in focus
        if focused_harness and top.endswith(expect_activity):
            # M30 run14: Settings came back *after* the first check (its activity
            # resumed during the transition), so the product's very next call saw
            # `hard_baseline (com.android.settings)`. Require the app to stay on
            # top for a short bounded window before declaring it foreground.
            # Keep this cheap (2 x 0.3 s): run16 showed a slow confirmation
            # pushing `am start` to ~14 s, past the suite's own 5 s window.
            stable += 1
            if stable >= 2:
                return True
            time.sleep(0.3)
            continue
        stable = 0
        if top and APP in top and "Fixture" in top:
            # Only dismiss the fixture, and only once per fixture sighting:
            # a second BACK would land on MainActivity and finish the task.
            adb("shell", "input", "keyevent", "4")
            time.sleep(1.2)
            continue
        if "NotificationShade" in (focus or ""):
            adb("shell", "cmd", "statusbar", "collapse")
            time.sleep(0.6)
            continue
        start(MAIN)
        time.sleep(0.7)
    log(f"ensure_app_foreground: still focus={foreground()} top={top_activity()}")
    return False


def start(component, *extra):
    adb("shell", "am", "start", "-n", component, *extra)
    time.sleep(1.6)


def bound():
    out = adb("shell", "dumpsys", "accessibility")
    if "Bound services" not in out:
        return False
    return "PhoneAgentService" in out.split("Bound services", 1)[1][:800]


def _find_service_entry():
    """Scroll the accessibility settings list until the service row is visible.

    M30: the "downloaded/installed services" section sits far below the fold; a
    single small swipe never reached it and the driver reported
    `entry not found` while the app was installed and the row existed.
    """
    adb("shell", "am", "start", "-a", "android.settings.ACCESSIBILITY_SETTINGS")
    time.sleep(2.6)
    # The settings list keeps its previous scroll position, so "Downloaded apps"
    # can be off-screen above. Reset to the top, then walk down.
    for _ in range(4):
        adb("shell", "input", "swipe", "540", "400", "540", "2100", "300")
        time.sleep(0.7)
    for step in range(10):
        xml = dump_ui(f"a11y-list-{step}")
        entry = find(xml, text="Kelivo Phone Agent")
        if entry is not None:
            return entry
        adb("shell", "input", "swipe", "540", "2000", "540", "700", "400")
        time.sleep(1.0)
    return None


def _service_switch():
    entry = _find_service_entry()
    if entry is None:
        log("service switch: entry not found")
        return None
    tap_node(entry)
    time.sleep(2.6)
    detail = dump_ui("a11y-detail")
    sw = find(detail, rid="switch_widget", cls="Switch") or find(detail, cls="Switch")
    if sw is None:
        log("service switch: switch not found")
    return sw


def _confirm_dialog(labels=("Allow", "允许", "OK", "确定", "Turn off", "Stop", "关闭")):
    xml = dump_ui("a11y-confirm")
    for label in labels:
        btn = find(xml, text=label, button_only=True)
        if btn is not None:
            tap_node(btn)
            log(f"confirmed with {label}")
            return True
    return False


def enable_service(require_bound=True, navigate=True):
    ok = _enable_service_inner(require_bound, navigate=navigate)
    # The suite runs inside the app process: leaving Settings in the foreground
    # lets Android freeze the backgrounded app and the test stalls silently.
    ensure_app_foreground()
    return ok


def wait_for_binding(timeout=90):
    """Wait until the accessibility service is bound, never navigating.

    M30 run14/run16: `PHONE_AGENT_ENABLE_SERVICE_NOW` re-opened the Settings
    detail page *after* the suite had already returned to the app, and left it
    on top; the product's very next call then returned
    `hard_baseline (com.android.settings)`. When the service is already enabled,
    the host only has to wait for the system to bind it.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        if bound():
            log("wait_for_binding: bound")
            ensure_app_foreground()
            return True
        time.sleep(1.5)
    log("wait_for_binding: still unbound, falling back to navigation")
    return enable_service(navigate=True)


def _enable_service_inner(require_bound=True, navigate=True):
    if not navigate:
        # The switch is already on; do not reopen Settings just to confirm it.
        if bound():
            return True
        return wait_for_binding()
    for attempt in range(4):
        # Reuse the page we are already on when possible: a fresh `am start`
        # plus list dump costs 10-20 s and makes host actions lag the test.
        sw = _current_switch() or _service_switch()
        if sw is not None:
            if sw.get("checked") != "true":
                tap_node(sw)
                time.sleep(2.2)
                _confirm_dialog()
            else:
                log("enable_service: switch already on")
        time.sleep(2.5)
        if not require_bound:
            return True
        if bound():
            log("enable_service: bound")
            return True
        # Switch reported on but no bound service: cycle it off and on again
        # (the accessibility binding is torn down by the APK reinstall).
        log(f"enable_service: not bound (attempt {attempt + 1}), cycling the switch")
        sw = _service_switch()
        if sw is None:
            continue
        if sw.get("checked") == "true":
            tap_node(sw)
            time.sleep(2.0)
            _confirm_dialog()
            time.sleep(2.0)
            sw = _service_switch()
            if sw is None:
                continue
        tap_node(sw)
        time.sleep(2.2)
        _confirm_dialog()
        time.sleep(3.0)
        if bound():
            log("enable_service: bound after cycle")
            return True
    log("enable_service: FAILED")
    return False


_detail: dict = {"switch": None, "page": None}

# Sentinel for informational markers that need no host action. Kept distinct from
# None so the dispatcher can skip the ordered queue entirely instead of queuing a
# no-op that delays the real `am start`.
_NOOP = object()


def open_service_detail():
    """Open the a11y details page once and cache the switch bounds.

    M30 run11: every action used to re-`am start` settings and re-dump the list,
    costing 10-20 s each. The queue therefore fell ~30 s behind the test: the
    "turn off" confirmation landed *after* the test had already re-enabled, left
    Settings on top, and the restart screenshot saw `hard_baseline
    (com.android.settings)`.
    """
    sw = _service_switch()
    _detail["switch"] = sw
    log(f"open_service_detail: switch={'found' if sw else 'missing'}")
    return sw is not None


def _current_switch():
    if _detail.get("switch"):
        return _detail["switch"]
    return _service_switch()


def _tap_switch_now(sw):
    tap_node(sw)
    time.sleep(1.4)
    # The confirm dialog reuses the same click; find the button immediately.
    return _confirm_dialog(labels=("Turn off", "Stop", "关闭", "OK", "确定"))


def open_disable_dialog():
    sw = _current_switch()
    if sw is None:
        return False
    if sw.get("checked") != "true":
        log("open_disable_dialog: service already off")
        return True
    tap_node(sw)
    time.sleep(1.4)
    log("open_disable_dialog: dialog opened")
    return True


def confirm_disable():
    for label in ("Turn off", "Stop", "关闭", "OK", "确定"):
        xml = dump_ui("a11y-disable-confirm")
        btn = find(xml, text=label)
        if btn is not None:
            tap_node(btn)
            log(f"confirm_disable: {label}")
            time.sleep(0.8)
            _detail["switch"] = None
            # Do not leave Settings on top after the service is off: the test
            # immediately needs the app in the foreground.
            adb("shell", "am", "start", "-n", MAIN)
            time.sleep(0.8)
            return True
    log("confirm_disable: no confirm button")
    return False


def open_shade():
    """Open the notification shade with real host touches.

    M30 finding: this loop used to run a fixed 13s. It kept swiping after the
    suite had already observed the denial and asked the host to recover, which
    re-opened the shade; every later tree read then failed with
    `system_window_denied (com.android.systemui, hard_baseline)` and the failure
    text printed 前台包名：未知. The loop now stops as soon as the shade is
    actually focused, and `_shade_stop` cancels it on recover.
    """
    _shade_stop.clear()
    end = time.time() + 12
    while time.time() < end and not _shade_stop.is_set():
        adb("shell", "input", "swipe", "540", "5", "540", "1200", "300")
        time.sleep(0.6)
        focus, _ = foreground()
        if focus and "NotificationShade" in focus:
            log("open_shade: shade focused")
            return
    log(f"open_shade: done (cancelled={_shade_stop.is_set()})")


def recover_from_shade():
    """Close the shade and bring the harness back, without finishing the task.

    Correction #2. This function used to send an unconditional `keyevent 4`.
    When `cmd statusbar collapse` had already closed the shade, that BACK landed
    on MainActivity and *finished* it, and the follow-up `am start` created a
    brand new task; after that relaunch the product could not resolve the
    foreground window type for a while and every tree read returned
    `window_type_unknown`.

    Evidence caveat: that round's device logcat showed the task CLOSE transition
    and the product's `windowType exhausted ...` line, but **neither original
    line was kept** (the driver's logcat capture was not running then). What is
    kept is the count: `run9.log` has 30 `window_type_unknown` tree results,
    `run5.log` has 0. So: never send BACK.
    """
    _shade_stop.set()
    time.sleep(0.4)
    for _ in range(6):
        adb("shell", "cmd", "statusbar", "collapse")
        time.sleep(0.5)
        focus, _ = foreground()
        if focus and "NotificationShade" not in focus:
            break
    if not ensure_app_foreground():
        log(f"recover_from_shade: focus still {foreground()}")
    log(f"recover_from_shade: focus={foreground()} top={top_activity()}")


def unlock():
    adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1.2)
    adb("shell", "wm", "dismiss-keyguard")
    time.sleep(1.2)
    adb("shell", "input", "swipe", "540", "1800", "540", "700", "300")
    time.sleep(1.2)
    adb("shell", "wm", "dismiss-keyguard")
    time.sleep(1.2)


def secure_window():
    """A foreground secure window cannot be dismissed by `input keyevent 4` on
    the fixture when the activity swallows back; use finish via am start of the
    test app instead. The suite drives the fixture itself, so nothing to do."""
    return None


def return_to_app():
    # The shade may be open (overlay host-touch case). A stale `hard_baseline`
    # denial would make every follow-up tree read fail with 前台包名：未知.
    # Also handles the same-package fixture activity sitting on top of the task.
    ensure_app_foreground()
    log(f"return_to_app: focus={foreground()} top={top_activity()}")


def open_permission_dialog():
    adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1.2)
    start(FIXTURE, "--ez", "requestPermission", "true")
    # The suite requires the host to confirm the real GrantPermissionsActivity
    # before it accepts a `no_window` result; record that check in the log.
    for _ in range(10):
        focus, _ = foreground()
        if focus and "grantpermission" in focus.lower():
            log(f"permission dialog confirmed: {focus}")
            return
        time.sleep(0.8)
    log(f"permission dialog NOT confirmed, focus={foreground()}")


def dismiss_permission():
    # BACK only when the permission dialog is actually the focused window;
    # an unconditional BACK can finish MainActivity and force a task relaunch.
    focus, _ = foreground()
    if focus and "permission" in (focus or "").lower():
        adb("shell", "input", "keyevent", "4")
        time.sleep(1.0)
    else:
        log(f"dismiss_permission: dialog not focused ({focus}), no BACK sent")
    out = adb("shell", "dumpsys", "package", APP)
    granted = re.search(r"POST_NOTIFICATIONS: granted=(\w+)", out)
    log(f"POST_NOTIFICATIONS after dismiss: {granted.group(1) if granted else 'unknown'}")
    ensure_app_foreground()


MARKERS = {
    # Recovery path only: setUpAll prints this once when the suite needs the
    # service enabled. It is the *only* marker allowed to navigate the Settings
    # UI; the restart case must use ENABLE_SERVICE_NOW so the two never race
    # (P2-4 / M31: no concurrent ENABLE and WAITING triggers).
    "PHONE_AGENT_WAITING_FOR_SERVICE": lambda: enable_service(),
    "PHONE_AGENT_SECURE_ON": lambda: start(SECURE_FIXTURE, "--ez", "secure", "true"),
    "PHONE_AGENT_STALE_WINDOW": lambda: start(FIXTURE, "--ez", "secure", "false"),
    "PHONE_AGENT_SECURE_OFF": lambda: start(SECURE_FIXTURE, "--ez", "secure", "false"),
    "PHONE_AGENT_OVERLAY_FIXTURE": lambda: start(FIXTURE, "--ez", "secure", "false"),
    "PHONE_AGENT_OVERLAY_ANIMATION": _NOOP,
    "PHONE_AGENT_OVERLAY_HOST_TOUCH": lambda: open_shade(),
    "PHONE_AGENT_OVERLAY_HOST_TOUCH_RECOVER": lambda: recover_from_shade(),
    "PHONE_AGENT_ROTATION_HOST_ACTION": _NOOP,
    # `home` / `recents` are performed by the product input action itself; the
    # marker is informational only.
    "PHONE_AGENT_HOME": _NOOP,
    "PHONE_AGENT_RECENTS": _NOOP,
    "PHONE_AGENT_PERMISSION_WINDOW": lambda: open_permission_dialog(),
    "PHONE_AGENT_PERMISSION_WINDOW_RETRY": lambda: (
        unlock(), open_permission_dialog()
    ),
    "PHONE_AGENT_DISMISS_PERMISSION": lambda: dismiss_permission(),
    "PHONE_AGENT_LOCK_SCREEN": lambda: adb("shell", "input", "keyevent", "26"),
    "PHONE_AGENT_UNLOCK_SCREEN": lambda: unlock(),
    "PHONE_AGENT_PREPARE_SERVICE_DISABLE": lambda: open_service_detail(),
    "PHONE_AGENT_OPEN_DISABLE_DIALOG": lambda: open_disable_dialog(),
    "PHONE_AGENT_DISABLE_DURING_PENDING": lambda: confirm_disable(),
    # Never navigates: the switch is already on, so only wait for the binding and
    # confirm the app is really back in front.
    "PHONE_AGENT_ENABLE_SERVICE_NOW": lambda: wait_for_binding(),
    "PHONE_AGENT_RETURN_TO_APP": lambda: return_to_app(),
}

# The permission flow prints a long instruction; match prefix only.

action_queue = queue.Queue()
_shade_stop = threading.Event()


def dispatch(marker, source):
    log(f"marker {marker} (from {source})")
    if marker == "PHONE_AGENT_OVERLAY_HOST_TOUCH_RECOVER":
        # Cancel an in-flight shade swipe before waiting for the action lock, so
        # the recovery does not sit behind the loop it is meant to stop.
        _shade_stop.set()
    action = MARKERS.get(marker)
    if action is not None and action is _NOOP:
        # Informational markers (home/recents are executed by the product
        # input action itself). They must not take a slot in the ordered
        # queue: run14/run15 showed them delaying the real `am start`.
        return
    # One FIFO worker: host actions must run in the order the suite asked for
    # them. Round 3 showed interleaved actions (the disable dialog was opened
    # after the "confirm" marker had already been handled).
    action_queue.put((marker, action))


def action_worker():
    while True:
        item = action_queue.get()
        if item is None:
            return
        marker, action = item
        try:
            action()
            log(f"after {marker}: focus={foreground()[0]} top={top_activity()}")
        except Exception as exc:
            log(f"marker {marker} action failed: {exc!r}")
        finally:
            action_queue.task_done()


def scan_line(line, source):
    """Dispatch only on real host-step lines.

    Two accepted shapes:
      - `MARKER: instruction` (suite `_hostStep` output)
      - the bare `MARKER` line (`_waitForService` prints
        `PHONE_AGENT_WAITING_FOR_SERVICE` with no colon)

    M30: the suite's own failure text embeds a marker name
    (`等待 ... 超时（标记 PHONE_AGENT_RETURN_TO_APP）`). Matching a marker
    anywhere in a line fired a spurious `am start` while the test was still
    running (run5 line 173); requiring line start plus exactly these two shapes
    keeps that fixed.
    """
    stripped = line.rstrip("\n\r")
    for marker in MARKERS:
        if stripped == marker:
            dispatch(marker, source)
            return
        if stripped.startswith(marker + ":"):
            dispatch(marker, source)
            return


def tail_logcat(stop):
    """Record device logs only.

    Dispatch is driven by the flutter test stdout alone: the suite prints
    `PHONE_AGENT_RETURN_TO_APP` from several call sites, and a per-marker
    dedupe window swallowed the second one (M30 round 3: the app was never
    returned to after `recents`). A device-log copy would also deliver every
    marker twice, and `KEYCODE_POWER` is a toggle.
    """
    adb("logcat", "-c")
    proc = subprocess.Popen(
        ["adb", "-s", SERIAL, "logcat", "-v", "brief"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    try:
        for line in proc.stdout:
            if stop.is_set():
                break
            if "PHONE_AGENT_" in line:
                with open(os.path.join(RUN_DIR, "logcat.log"), "a", encoding="utf-8") as fh:
                    fh.write(line)
    finally:
        proc.terminate()


def main():
    open(LOG, "w", encoding="utf-8").close()
    flutter = os.environ.get("FLUTTER_BIN") or shutil.which("flutter") or "flutter.bat"
    cmd = [flutter, "test", "integration_test/phone_agent_exception_test.dart", "-d", SERIAL]
    # Args may carry a regex with parentheses; pass them as env to survive shells.
    extra = os.environ.get("TEST_ARGS")
    if extra:
        import shlex
        cmd += shlex.split(extra)
    elif len(sys.argv) > 1:
        cmd += sys.argv[1:]
    log("starting: " + " ".join(cmd))
    threading.Thread(target=action_worker, daemon=True).start()
    stop = threading.Event()
    threading.Thread(target=tail_logcat, args=(stop,), daemon=True).start()
    time.sleep(2)

    proc = subprocess.Popen(
        cmd, cwd=APP_TREE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    started = time.time()
    try:
        for line in proc.stdout:
            with open(LOG, "a", encoding="utf-8") as fh:
                fh.write(line)
            if "PHONE_AGENT_" in line:
                scan_line(line, "stdout")
            if "All tests passed" in line or "Some tests failed" in line:
                log("suite finished")
    finally:
        proc.wait(timeout=180)
        stop.set()
        log(f"flutter test exit={proc.returncode} elapsed={int(time.time() - started)}s")
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
