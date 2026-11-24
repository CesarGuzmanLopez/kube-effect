#!/usr/bin/env python3
"""Unit check of package/contents/ui/constants.js under the QML engine.

constants.js is the boundary between kwinrc types and the scene: a Color entry
arrives as a QColor and a Url entry as a url value (not a string), so the
conversions cannot be tested with plain Python. The QML harness next to this
script exposes such properties and runs the real helpers.

Skipped (exit 0) when PySide6 is missing, so CI does not depend on it.
"""

import os
import sys

try:
    from PySide6.QtCore import QObject, Property, QUrl, qInstallMessageHandler
    from PySide6.QtGui import QColor
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    from PySide6.QtWidgets import QApplication
except ImportError:  # pragma: no cover - optional dependency
    print("check-constants: skipped (PySide6 is not installed)")
    sys.exit(0)

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def forward_qml_warnings(_mode, _context, message):
    if (
        "TypeError" in message
        or "ReferenceError" in message
        or "is not defined" in message
    ):
        print(f"qml: {message}")


class Holder(QObject):
    """Same value types KConfigLoader's ItemColor/ItemUrl hand QML."""

    def __init__(self):
        super().__init__()
        self._values = {
            "opaque": QColor("#212427"),
            "opaqueAlpha": QColor("#ff212427"),
            "translucent": QColor("#806ee7ff"),
            "fileUrl": QUrl("file:///home/user/My%20Wall.jpg"),
            "emptyUrl": QUrl(""),
            "bareUrl": QUrl("/home/user/wall.jpg"),
        }

    @Property(QColor, constant=True)
    def opaque(self):
        return self._values["opaque"]

    @Property(QColor, constant=True)
    def opaqueAlpha(self):
        return self._values["opaqueAlpha"]

    @Property(QColor, constant=True)
    def translucent(self):
        return self._values["translucent"]

    @Property(QUrl, constant=True)
    def fileUrl(self):
        return self._values["fileUrl"]

    @Property(QUrl, constant=True)
    def emptyUrl(self):
        return self._values["emptyUrl"]

    @Property(QUrl, constant=True)
    def bareUrl(self):
        return self._values["bareUrl"]


def main():
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    qInstallMessageHandler(forward_qml_warnings)
    application = QApplication(sys.argv)  # noqa: F841 - required by the QML engine

    engine = QQmlEngine()
    holder = Holder()  # keep a reference: a temporary would be collected
    engine.rootContext().setContextProperty("h", holder)
    component = QQmlComponent(engine)
    component.loadUrl(QUrl.fromLocalFile(str(ROOT / "scripts/check-constants.qml")))
    if component.isError():
        print("check-constants: FAIL")
        for error in component.errors():
            print(f" - {error.toString()}")
        return 1
    harness = component.create()
    if harness is None:
        print("check-constants: FAIL could not create the QML harness")
        return 1
    # Component.onCompleted runs synchronously at create(), so no event loop.
    application.processEvents()
    print(harness.property("log"))
    ok = harness.property("ok")
    print("check-constants:", "OK" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
