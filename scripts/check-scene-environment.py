#!/usr/bin/env python3
"""Load check of the SkyBox SceneEnvironment under the plain QML engine.

The dimming-while-rotating feature touches probeExposure, a property that only
exists on QtQuick3D's SceneEnvironment. qmllint of the effect cannot resolve
KWin/Quick3D types alone, so this script builds the same fragment (SceneEnvironment
inside a Loader, probeExposure bound to a property with a 120 ms Behavior) in a
real QML engine and drives it through the two values the effect uses: 1.0 (still)
and 0.4 (rotating, 40 % dim). Any unknown property (TypeError) or broken binding
after the animation fails the check.

Skipped (exit 0) when PySide6 or QtQuick3D is missing, so CI does not depend on it.
The renderer is never used: there is no View3D, only the environment object.
"""

import os
import sys
import time

try:
    from PySide6.QtCore import QUrl, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
except ImportError:  # pragma: no cover - optional dependency
    print("check-scene-environment: skipped (PySide6 is not installed)")
    sys.exit(0)

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Cap on waiting for the 120 ms Behavior; generous so a busy CI still passes.
SETTLE_SECONDS = 2.0

messages: list[str] = []


def collect_filetells(_mode, _context, message):
    if (
        "TypeError" in message
        or "ReferenceError" in message
        or "is not defined" in message
        or "Cannot assign" in message
        or "non-existent" in message
    ):
        messages.append(message)


def settle(application, milliseconds):
    """Run the event loop until the property animation has finished."""
    deadline = time.monotonic() + milliseconds / 1000.0
    while time.monotonic() < deadline:
        application.processEvents()
        time.sleep(0.005)
    application.processEvents()


# Negative control: an environment property that does not exist must make the
# component fail, otherwise a passing load check would prove nothing.
SELFTEST_BAD = b"""
import QtQuick
import QtQuick3D

SceneEnvironment {
    probeExposureTypo: 1.0
}
"""

SELFTEST_GOOD = b"""
import QtQuick
import QtQuick3D

SceneEnvironment {
    backgroundMode: SceneEnvironment.SkyBox
    probeExposure: 0.4
}
"""


def selftest(engine):
    """The harness must reject an unknown property and accept a real one."""
    failures = []
    bad = QQmlComponent(engine)
    bad.setData(SELFTEST_BAD, QUrl("qrc:/selftest-bad.qml"))
    if not bad.isError():
        failures.append("an unknown SceneEnvironment property did not fail")
    good = QQmlComponent(engine)
    good.setData(SELFTEST_GOOD, QUrl("qrc:/selftest-good.qml"))
    if good.isError():
        failures.append("a valid SceneEnvironment fragment failed")
    return failures


def main():
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    # Same software-only setup: no GPU and no window surface is needed.
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    qInstallMessageHandler(collect_filetells)
    application = QGuiApplication(sys.argv)

    engine = QQmlEngine()
    if "--selftest" in sys.argv[1:]:
        failures = selftest(engine)
        for failure in failures:
            print(f"FAIL {failure}")
        print("check-scene-environment --selftest:", "OK" if not failures else "FAIL")
        return 0 if not failures else 1
    component = QQmlComponent(engine)
    component.loadUrl(
        QUrl.fromLocalFile(str(ROOT / "scripts/check-scene-environment.qml"))
    )
    if component.isError():
        print("check-scene-environment: FAIL")
        for error in component.errors():
            print(f" - {error.toString()}")
        return 1
    harness = component.create()
    if harness is None:
        print("check-scene-environment: FAIL could not create the QML harness")
        return 1
    application.processEvents()

    log = [harness.property("log") or ""]
    ok = bool(harness.property("ok"))
    environment = harness.property("environment")
    if environment is None:
        print("\n".join(log))
        print("check-scene-environment: FAIL (no SceneEnvironment)")
        return 1

    def close(actual, expected):
        return abs(float(actual) - expected) <= 1e-5

    # Still cube: base exposure, untouched by the dim amount.
    if not close(environment.property("probeExposure"), 1.0):
        log.append(
            f"FAIL exposure(still) = {environment.property('probeExposure')} (expected 1)"
        )
        ok = False
    else:
        log.append("PASS exposure(still) = 1")

    # Rotating with a 40 % dim: 1.0 - 0.4, reached through the Behavior.
    harness.setProperty("exposure", 0.4)
    settle(application, 400)
    value = environment.property("probeExposure")
    if not close(value, 0.4):
        log.append(f"FAIL exposure(rotating 40%) = {value} (expected 0.4)")
        ok = False
    else:
        log.append("PASS exposure(rotating 40%) = 0.4")

    # Back to the base value: the same binding must still be alive.
    harness.setProperty("exposure", 1.0)
    settle(application, 400)
    value = environment.property("probeExposure")
    if not close(value, 1.0):
        log.append(f"FAIL exposure(still again) = {value} (expected 1)")
        ok = False
    else:
        log.append("PASS exposure(still again) = 1")

    if messages:
        ok = False
        for message in messages:
            log.append(f"FAIL qml: {message.strip()}")

    print("\n".join(log))
    print("check-scene-environment:", "OK" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
