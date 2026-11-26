#!/usr/bin/env python3
"""Render test of the 360 video path in the real ScreenView.qml.

The 360 clip is painted on a sphere inside the View3D (ADR-020) because Qt
Quick 3D refuses a Texture.sourceItem as a light probe. That failure mode is
invisible in a lint run: the effect loaded fine and simply painted nothing, so a
script has to *render* the real file and look at the pixels.

What it does:
  * writes a stub "org.kde.kwin" QML module (SceneView, Workspace and the three
    window models) in a temporary directory, so ScreenView.qml and Cube.qml load
    outside KWin;
  * feeds a fake "effect" context object (Background=Video, Equirect, rotate on)
    pointing at a clip given on the command line;
  * renders the real ScreenView.qml and grabs the window.

Passing means the frame has many distinct colours (the video is on screen). A
uniform frame is exactly the "black background" bug.

Skipped (exit 0) without PySide6 or without a real (non-offscreen) platform:
Qt Quick 3D does not render on the offscreen plugin, so CI cannot run this.
"""

import os
import sys
import tempfile
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=DeprecationWarning)

try:
    from PySide6.QtCore import QTimer, QUrl
    from PySide6.QtGui import QGuiApplication, QImage
    from PySide6.QtQml import QQmlEngine, QQmlPropertyMap
    from PySide6.QtQuick import QQuickView
except ImportError:  # pragma: no cover - optional dependency
    print("check-video-dome: skipped (PySide6 is not installed)")
    sys.exit(0)

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = ROOT / "package/contents/ui"
DEFAULT_CLIP = (
    Path.home()
    / "Imágenes/stock-video-river-in-the-rainforest-philippines-bohol-virtual-reality-360.mp4"
)

STUB_MODULE = {
    "qmldir": """module org.kde.kwin
singleton SceneView 1.0 SceneView.qml
singleton Workspace 1.0 Workspace.qml
VirtualDesktopModel 1.0 VirtualDesktopModel.qml
WindowModel 1.0 WindowModel.qml
WindowFilterModel 1.0 WindowFilterModel.qml
WindowThumbnail 1.0 WindowThumbnail.qml
""",
    "SceneView.qml": """pragma Singleton
import QtQuick
QtObject {
    property var screen: null
}
""",
    "Workspace.qml": """pragma Singleton
import QtQuick
QtObject {
    signal currentDesktopChanged(var previous, var current, var screen)
    property var activeScreen: null
    property var cursorPos: Qt.point(0, 0)
    property var currentActivity: ""
    property var desktops: []
    function currentDesktopForScreen(screen) { return null; }
    function setCurrentDesktopForScreen(desktop, screen) {}
    function createDesktop() { return null; }
    function screenAt(pos) { return null; }
}
""",
    # The desktop role carries a real QObject (verified: ListModel.append()
    # keeps it and delegates read it back), because CubeFace declares
    # "required property QtObject desktop": rows without the role make the
    # delegate fail to build and the render test would never touch the faces
    # or the ADR-022 LOD. x11DesktopNumber is read by Cube.desktopAzimuth.
    "VirtualDesktopModel.qml": """import QtQuick
ListModel {
    id: vdm
    Component.onCompleted: {
        for (let n = 1; n <= 3; ++n) {
            // createQmlObject, not a Component child element: a ListModel
            // parses any nested element as a ListElement.
            const desktop = Qt.createQmlObject("import QtQuick; QtObject { property int x11DesktopNumber; property string name }", vdm);
            desktop.x11DesktopNumber = n;
            desktop.name = String(n);
            append({ "desktop": desktop, "x11DesktopNumber": n, "name": String(n) });
        }
    }
}
""",
    "WindowModel.qml": """import QtQuick
ListModel {
}
""",
    "WindowFilterModel.qml": """import QtQuick
ListModel {
    property var activity
    property var desktop
    property string screenName
    property var windowModel
}
""",
    "WindowThumbnail.qml": """import QtQuick
Item {
    property var wId
}
""",
}

# Background enum index for Video (see package/contents/config/main.xml).
BACKGROUND_VIDEO = 3
# Enough distinct colours to rule out a uniform clear/black frame.
MIN_COLOURS = 50


def write_stub_module(directory):
    target = Path(directory) / "org/kde/kwin"
    target.mkdir(parents=True, exist_ok=True)
    for name, contents in STUB_MODULE.items():
        (target / name).write_text(contents, encoding="utf-8")
    return Path(directory)


def configuration(clip):
    values = {
        "CubeFaceDisplacement": 100.0,
        "DistanceFactor": 1.75,
        "BorderActivate": "",
        "TouchBorderActivate": "",
        "MouseInvertedX": False,
        "MouseInvertedY": False,
        "SkyBox": "",
        "BackgroundVideo": QUrl.fromLocalFile(str(clip)).toString(),
        "Background": BACKGROUND_VIDEO,
        "BackgroundImageLayout": 0,  # Equirect
        "BackgroundImageFit": 0,
        "BackgroundImageRotate": True,
        "BackgroundColor": "#270001",
        "BackgroundColor2": "#ff8a00",
        "BackgroundGradientType": 0,
        "BackgroundGradientStop": 50,
        "BackgroundGradientRotation": 0,
        "DimWhileRotating": False,
        "DimWhileRotatingAmount": 40,
        "CursorScreenOnly": False,
    }
    model = QQmlPropertyMap()
    for key, value in values.items():
        model.insert(key, value)
    return model


def main(argv):
    clip = Path(argv[1]) if len(argv) > 1 else DEFAULT_CLIP
    if not clip.is_file():
        print(f"check-video-dome: skipped (no clip at {clip})")
        return 0

    # Qt Quick 3D does not render on the offscreen plugin and QGuiApplication
    # aborts with no platform at all, so bail out before creating it.
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        print("check-video-dome: skipped (no display; QtQuick3D needs a real platform)")
        return 0

    application = QGuiApplication(sys.argv[:1])
    if application.platformName() in ("offscreen", "minimal"):
        print(
            "check-video-dome: skipped (needs a real platform; QtQuick3D does not render offscreen)"
        )
        return 0

    with tempfile.TemporaryDirectory() as temporary:
        import_root = write_stub_module(temporary)

        effect = QQmlPropertyMap()
        # Keep the map in a local: as a temporary it is collected right after
        # insert() and QML then reads an empty object (Background = 0).
        config = configuration(clip)
        effect.insert("configuration", config)
        for key, value in {
            "visible": True,
            "activated": True,
            "cursorScreenName": "",
            "animationDuration": 400,
            "toEdges": 0,
        }.items():
            effect.insert(key, value)

        engine = QQmlEngine()
        engine.addImportPath(str(import_root))
        engine.rootContext().setContextProperty("effect", effect)

        view = QQuickView(engine, None)
        view.resize(640, 360)
        view.setSource(QUrl.fromLocalFile(str(UI_DIR / "ScreenView.qml")))
        if view.status() != QQuickView.Status.Ready:
            print("check-video-dome: FAIL")
            for error in view.errors():
                print(f" - {error.toString()}")
            return 1
        view.show()

        # ScreenView.qml is an Item with no implicit size; without this the
        # window would be 0x0 and the grab uniform.
        root = view.rootObject()
        root.setProperty("width", 640)
        root.setProperty("height", 360)

        result = {"ok": False}

        def check():
            root = view.rootObject()
            for property_name, expected in (
                ("backgroundMode", BACKGROUND_VIDEO),
                ("videoWanted", True),
                ("videoPainted", True),
                ("videoDomePainted", True),
            ):
                actual = root.property(property_name)
                status = "PASS" if actual == expected else "FAIL"
                print(f"{status} {property_name} = {actual}")
                if status == "FAIL":
                    result["ok"] = False
                    application.exit(1)
                    return

            # The dome samples the VideoOutput as Texture.sourceItem: while
            # wrapping, the output must STRETCH the full frame. Cover (the
            # default fit) crops the top and bottom of the equirect clip
            # (lost sky/ground, jumping horizon); Contain letterboxes black
            # bars into the sphere's poles. VideoOutput.Stretch == 0.
            # PySide has no converter for the QQuickVideoOutput::FillMode enum
            # (property("fillMode") raises RuntimeError), so the harness reads
            # the int mirror HullVideo.qml exposes on the output's parent item.
            probe = root.property("videoProbeItem")
            holder = probe.parent() if probe is not None else None
            fill = holder.property("fillModeValue") if holder is not None else None
            print(
                f"{'PASS' if fill == 0 else 'FAIL'} dome VideoOutput fillMode = {fill} (expected 0 = Stretch)"
            )
            if fill != 0:
                result["ok"] = False

            image = view.grabWindow().convertToFormat(QImage.Format_RGB32)
            colours = len(
                {
                    image.pixel(x, y)
                    for y in range(0, image.height(), 6)
                    for x in range(0, image.width(), 6)
                }
            )
            print(
                f"{'PASS' if colours >= MIN_COLOURS else 'FAIL'} video dome colours = {colours} (min {MIN_COLOURS})"
            )
            result["ok"] = colours >= MIN_COLOURS
            application.exit(0 if result["ok"] else 1)

        QTimer.singleShot(4000, check)
        code = application.exec()
        print("check-video-dome:", "OK" if result["ok"] else "FAIL")
        return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
