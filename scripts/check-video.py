#!/usr/bin/env python3
"""Load test of package/contents/ui/HullVideo.qml (needs a QML engine).

HullVideo.qml is the only file importing QtMultimedia, an optional module
(package qt6-multimedia). ScreenView.qml loads it with a Loader so that a
machine without the module keeps the whole effect alive and falls back to
BackgroundColor. This test proves both paths without KWin:

  * the real HullVideo.qml is instantiated (Loader.Ready, item created, the
    VideoOutput it exposes for Texture.sourceItem exists);
  * when QtMultimedia is absent the Loader ends in Error and creates no item,
    which is exactly what ScreenView catches to warn once and paint the colour;
  * a Loader pointing at a missing file also ends in Error (simulated
    fallback), so one broken item cannot take the rest of the scene down;
  * a MediaPlayer given a non-existent clip keeps the item alive (error path,
    not a QML error).

No video is played: the harness never renders and no file is needed.

Skipped (exit 0) when PySide6 is missing, so CI does not depend on it.
"""

import os
import sys

try:
  from PySide6.QtCore import QMetaObject, QUrl, qInstallMessageHandler
  from PySide6.QtQml import QQmlComponent, QQmlEngine
  from PySide6.QtWidgets import QApplication
except ImportError:  # pragma: no cover - optional dependency
  print("check-video: skipped (PySide6 is not installed)")
  sys.exit(0)

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = ROOT / "package/contents/ui"


def forward_qml_errors(_mode, context, message):
  if (
    "TypeError" in message
    or "ReferenceError" in message
    or "is not defined" in message
    or "Cannot assign" in message
  ):
    print(f"qml: {message}")


def module_available(engine, name):
  """True when QtMultimedia/qmldir exists under a real QML import root."""
  for entry in engine.importPathList():
    if not entry.startswith("/"):
      continue
    if (Path(entry) / name / "qmldir").is_file():
      return True
  return False


def main():
  os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
  qInstallMessageHandler(forward_qml_errors)
  application = QApplication(sys.argv)

  engine = QQmlEngine()
  has_multimedia = module_available(engine, "QtMultimedia")

  component = QQmlComponent(engine)
  component.loadUrl(QUrl.fromLocalFile(str(ROOT / "scripts/check-video.qml")))
  if component.isError():
    print("check-video: FAIL")
    for error in component.errors():
      print(f" - {error.toString()}")
    return 1
  harness = component.create()
  if harness is None:
    print("check-video: FAIL could not create the QML harness")
    return 1

  # The Python message handler must be gone before any MediaPlayer exists.
  # Creating one spawns QtMultimedia's PipeWire thread; when that thread emits
  # a warning it needs the GIL, which the thread blocked inside
  # setProperty() still holds, and the process deadlocks (reproduced
  # 2026-11-25: `make check` hung here until the 50 s timeout). The harness
  # asserts on Loader.status and item existence, so it needs no console text.
  qInstallMessageHandler(None)

  harness.setProperty("videoUrl", QUrl.fromLocalFile(str(UI_DIR / "HullVideo.qml")))
  harness.setProperty(
    "brokenUrl", QUrl.fromLocalFile(str(UI_DIR / "MissingHullVideo.qml"))
  )
  harness.setProperty("expectModule", has_multimedia)
  # Local Loaders load synchronously, but let the engine settle before asking.
  for _ in range(3):
    application.processEvents()

  # A source that does not exist must leave the item alive (MediaPlayer error,
  # not a QML error), mimicking a user pointing at a removed clip. It also
  # covers the "did the user pick a removable drive?" case without a crash.
  video = harness.property("videoItem")
  if video is not None:
    video.setProperty("source", QUrl.fromLocalFile(str(UI_DIR / "does-not-exist.mp4")))
    video.setProperty("playing", True)
    for _ in range(3):
      application.processEvents()

  QMetaObject.invokeMethod(harness, "run")
  print(harness.property("log"))
  print(
    f"check-video: QtMultimedia {'available' if has_multimedia else 'absent (fallback path)'}"
  )
  ok = harness.property("ok")
  print("check-video:", "OK" if ok else "FAIL")
  return 0 if ok else 1


if __name__ == "__main__":
  sys.exit(main())
