#!/usr/bin/env python3
"""Render test of the 360 video path in the real ScreenView.qml.

The 360 clip is painted on a sphere inside the View3D (ADR-020) because Qt
Quick 3D refuses a Texture.sourceItem as a light probe. That failure mode is
invisible in a lint run: the effect loaded fine and simply painted nothing, so a
script has to *render* the real file and look at the pixels.

What it does:
  * writes a stub "org.kde.kwin" QML module (SceneView, Workspace and the three
    window models) in a temporary directory, so ScreenView.qml and Cube.qml load
    outside KWin. The model size comes from the "stubDesktopCount" context
    property; Workspace.currentDesktopForScreen returns a REAL desktop object
    (Cube.desktopAzimuth dereferences .x11DesktopNumber: with null it threw a
    TypeError and the rotation binding died silently, unnoticed by the test);
  * each scenario runs in a CHILD PROCESS; after a warm-up load caches every
    QML type, a message handler accumulates QML errors (TypeError /
    ReferenceError / "is not defined", the signature list of
    check-constants.py) and the scenario fails if any appears; legitimate Qt
    warnings are NOT failures, only those three signatures are (the parent
    additionally re-scans the captured output as a second net);
  * feeds a fake "effect" context object (Background=Video, Equirect, rotate on,
    DebugOverlay on) pointing at a clip given on the command line;
  * scenario A (3 desktops): renders the real ScreenView.qml and grabs the
    window; a uniform frame is exactly the "black background" bug;
  * scenario B (2 desktops, ADR-024 sheet): same harness, and instead of new
    colour expectations it asserts the sheet geometry through the DebugOverlay
    text (isSheet, tick 180, faceCount 2, no azimuth limit, viewRadius).

Skipped (exit 0) without PySide6 or without a real (non-offscreen) platform:
Qt Quick 3D does not render on the offscreen plugin, so CI cannot run this.
"""

import os
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=DeprecationWarning)

try:
    from PySide6.QtCore import QTimer, QUrl, qInstallMessageHandler
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
    id: ws
    signal currentDesktopChanged(var previous, var current, var screen)
    property var activeScreen: null
    property var cursorPos: Qt.point(0, 0)
    property var currentActivity: ""
    property var desktops: []
    // A real desktop, not null: Cube.desktopAzimuth(currentDesktop) reads
    // .x11DesktopNumber in the polygon path and used to throw a TypeError
    // here, killing the state rotation binding without failing the test.
    // Parented to the singleton so the object outlives the binding.
    property var firstDesktop: Qt.createQmlObject("import QtQuick; QtObject { property int x11DesktopNumber: 1; property string name: \\"1\\" }", ws)
    function currentDesktopForScreen(screen) { return firstDesktop; }
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
    # stubDesktopCount (context property) sets the size: 3 = polygon, 2 = sheet.
    "VirtualDesktopModel.qml": """import QtQuick
ListModel {
    id: vdm
    property int stubCount: (typeof stubDesktopCount === "number" && stubDesktopCount > 0) ? stubDesktopCount : 3
    Component.onCompleted: {
        for (let n = 1; n <= stubCount; ++n) {
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
    # One fake window per desktop so every DesktopView face carries a FLAT
    # COLOUR the render tests can identify (check-cylinder-overlap.py samples
    # pixels per face). internalId carries the desktop number: the stub maps
    # it to red/green/blue. The thumbnail fills the face by default; with the
    # stubFaceCoverage context property below 1 it leaves an alpha-0 border
    # (keeps the "wallpaper shows through the face texture" case visible in
    # the grabs: a blending material reveals it, an opaque one paints black).
    "WindowFilterModel.qml": """import QtQuick
ListModel {
    id: wfm
    property var activity
    property var desktop
    property string screenName
    property var windowModel
    Component.onCompleted: {
        if (desktop === null || desktop === undefined) {
            return;
        }
        const number = desktop.x11DesktopNumber;
        // createQmlObject: a ListModel parses any nested element as a ListElement.
        const win = Qt.createQmlObject("import QtQuick; QtObject { property string internalId; property real x; property real y; property int stackingOrder; property bool minimized }", wfm);
        win.internalId = "stub-" + number;
        win.x = 0;
        win.y = 0;
        win.stackingOrder = 0;
        win.minimized = false;
        append({ "window": win });
    }
}
""",
    "WindowThumbnail.qml": """import QtQuick
Item {
    id: thumb
    property var wId
    // Size to the DesktopView (the Repeater's parent): a plain delegate Item
    // has no implicit size, and the render tests need the colour to cover the
    // face. 72 % leaves an alpha-0 border around the colour block.
    // stubFaceCoverage (context property): 1 fills the whole face (ordering
    // tests, no holes); <1 leaves an alpha border (transparency tests).
    readonly property real cover: (typeof stubFaceCoverage === "number" && stubFaceCoverage > 0) ? stubFaceCoverage : 1
    width: parent !== null ? parent.width * cover : 0
    height: parent !== null ? parent.height * cover : 0
    Rectangle {
        anchors.fill: parent
        color: String(thumb.wId).endsWith("-1") ? "#ff0000"
            : String(thumb.wId).endsWith("-2") ? "#00ff00"
            : String(thumb.wId).endsWith("-3") ? "#0000ff"
            : "#ffa500"
    }
}
""",
}

# Background enum index for Video (see package/contents/config/main.xml).
BACKGROUND_VIDEO = 3
# Enough distinct colours to rule out a uniform clear/black frame.
MIN_COLOURS = 50
# Only these three signatures fail a scenario (the check-constants.py pattern).
# Other qWarnings are legitimate Qt chatter (shader backend, vsync, ...) and
# must NOT break the gate.
QML_ERROR_SIGNATURES = ("TypeError", "ReferenceError", "is not defined")


def write_stub_module(directory):
    target = Path(directory) / "org/kde/kwin"
    target.mkdir(parents=True, exist_ok=True)
    for name, contents in STUB_MODULE.items():
        (target / name).write_text(contents, encoding="utf-8")
    return Path(directory)


def configuration(clip, overlay):
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
        # ADR-023 overlay: scenario B asserts the sheet geometry THROUGH
        # debugInfo, so the live state must be composed there. In the polygon
        # scenario it stays OFF: the red monospace Text is composited inside
        # grabWindow(), and its outlined pixels would feed the colour set
        # counted against MIN_COLOURS - the dome proof must not rest on the
        # overlay's own colours.
        "DebugOverlay": overlay,
    }
    model = QQmlPropertyMap()
    for key, value in values.items():
        model.insert(key, value)
    return model


def run_scenario(
    application, import_root, clip, desktop_count, expectations, check_video
):
    """Build one engine+view, render, run the checks, return the exit code.

    expectations: list of (label, callable(root) -> bool) property assertions.
    check_video: run the full video-pipeline assertions (painted properties,
    fillMode, colour grab). Scenario B deliberately skips them: the clip decode
    already proved the video path in scenario A, and re-waiting for a frame in
    the sheet pass only adds timing flakiness, no coverage.

    Note on QML errors (review fix, second pass): a Python
    qInstallMessageHandler installed BEFORE the first setSource deadlocks this
    harness — the main thread blocks in QQmlTypeLoader::getType (setSource)
    while the QML thread waits for the GIL to deliver its parse-time
    qWarning (measured: 12 s hang, faulthandler trace inside QWaitCondition);
    and with no handler this PySide6 swallows every Qt message silently. The
    scenario therefore warms up the engine's type cache first WITHOUT a
    handler, installs one, and then creates the real view: all remaining
    messages (broken bindings, failed component creation, onCompleted
    errors) arrive on the main thread and are collected.
    """
    effect = QQmlPropertyMap()
    # Keep the map in a local: as a temporary it is collected right after
    # insert() and QML then reads an empty object (Background = 0).
    config = configuration(clip, overlay=not check_video)
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
    engine.rootContext().setContextProperty("stubDesktopCount", desktop_count)

    # Warm-up load (its own throwaway view): parses every QML file through the
    # QQmlTypeLoader thread with NO Python message handler installed. The
    # handler must come later: with one installed, a parse-time warning from
    # the loader thread blocks on the GIL while this thread sits inside
    # QQmlTypeLoader::getType waiting for that same thread (measured: 12 s
    # hang, faulthandler trace under QQuickView.setSource; and without a
    # handler this PySide6 silently swallows every Qt message, so the
    # check-constants.py accumulation only works once one is installed).
    warm = QQuickView(engine, None)
    warm.setSource(QUrl.fromLocalFile(str(UI_DIR / "ScreenView.qml")))
    if warm.status() != QQuickView.Status.Ready:
        print(f"check-video-dome: FAIL (count={desktop_count}, warm-up)")
        for error in warm.errors():
            print(f" - {error.toString()}")
        return 1
    warm.destroy()

    qml_errors = []

    def forward_qml_warnings(_mode, _context, message):
        if any(signature in message for signature in QML_ERROR_SIGNATURES):
            qml_errors.append(message)

    # Safe now: every type is cached by the engine, so the real load below
    # never blocks on the loader thread and this handler only ever runs on the
    # main thread (creation-phase bindings, timers).
    qInstallMessageHandler(forward_qml_warnings)

    view = QQuickView(engine, None)
    view.resize(640, 360)
    view.setSource(QUrl.fromLocalFile(str(UI_DIR / "ScreenView.qml")))
    if view.status() != QQuickView.Status.Ready:
        print(f"check-video-dome: FAIL (count={desktop_count}, engine)")
        for error in view.errors():
            print(f" - {error.toString()}")
        return 1
    view.show()

    # ScreenView.qml is an Item with no implicit size; without this the
    # window would be 0x0 and the grab uniform.
    root = view.rootObject()
    root.setProperty("width", 640)
    root.setProperty("height", 360)
    # Input OFF: this grab window really shows on the developer's desktop
    # for the duration of the check, and a stray pointer click would run
    # switchTo -> effect.deactivate(); the fake effect is a property map
    # without methods, so that click produced a harness-only TypeError that
    # failed the gate. This check validates pixels, not interaction. The
    # return value: if the enabled property ever disappears (or root stops
    # being an Item), setProperty silently returns False and the flaky-click
    # failure would come back LOUDLY here instead of haunting the gate as a
    # random TypeError. A plain assert would be stripped under python -O,
    # so this raises explicitly.
    if root.setProperty("enabled", False) is not True:
        raise RuntimeError("enabled property vanished: input is NOT switched off")

    failures = []

    def check():
        if not check_video:
            # Scenario B: sheet geometry only (plus the qml-error gate below).
            for label, assertion in expectations:
                try:
                    ok = bool(assertion(root))
                    detail = ""
                except Exception as error:  # noqa: BLE001  # report, do not crash
                    ok = False
                    detail = f" ({error})"
                print(f"{'PASS' if ok else 'FAIL'} [n={desktop_count}] {label}{detail}")
                if not ok:
                    failures.append(label)
            for message in qml_errors:
                print(f"FAIL [n={desktop_count}] qml error: {message}")
            if qml_errors:
                failures.append("qml-errors")
            application.exit(0 if not failures else 1)
            return

        for property_name, expected in (
            ("backgroundMode", BACKGROUND_VIDEO),
            ("videoWanted", True),
            ("videoPainted", True),
            ("videoDomePainted", True),
        ):
            actual = root.property(property_name)
            ok = actual == expected
            print(
                f"{'PASS' if ok else 'FAIL'} [n={desktop_count}] {property_name} = {actual}"
            )
            if not ok:
                failures.append(property_name)

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
            f"{'PASS' if fill == 0 else 'FAIL'} [n={desktop_count}] dome VideoOutput fillMode = {fill} (expected 0 = Stretch)"
        )
        if fill != 0:
            failures.append("fillMode")

        if not expectations:
            # (video-only scenarios) colour grab proves the dome painted.
            image = view.grabWindow().convertToFormat(QImage.Format_RGB32)
            colours = len(
                {
                    image.pixel(x, y)
                    for y in range(0, image.height(), 6)
                    for x in range(0, image.width(), 6)
                }
            )
            ok = colours >= MIN_COLOURS
            print(
                f"{'PASS' if ok else 'FAIL'} [n={desktop_count}] video dome colours = {colours} (min {MIN_COLOURS})"
            )
            if not ok:
                failures.append("colours")

        for label, assertion in expectations:
            try:
                ok = bool(assertion(root))
                detail = ""
            except Exception as error:  # noqa: BLE001  # report, do not crash
                ok = False
                detail = f" ({error})"
                failures.append(label)
            print(f"{'PASS' if ok else 'FAIL'} [n={desktop_count}] {label}{detail}")
            if not ok:
                failures.append(label)

        for message in qml_errors:
            print(f"FAIL [n={desktop_count}] qml error: {message}")
        if qml_errors:
            failures.append("qml-errors")

        application.exit(0 if not failures else 1)

    QTimer.singleShot(4000, check)
    code = application.exec()
    # Release the view/engine before the process leaves the scenario (the
    # child exits right after; teardown kept explicit for clarity).
    view.hide()
    view.destroy()
    engine.deleteLater()
    return code


def sheet_assertions():
    """Scenario B (ADR-024, 2 desktops): assert through the DebugOverlay text
    that the solid switched to the sheet. 640x360 gives viewRadius = 320,
    tick = 180, sheet = 1 and (with 2 desktops) lim = 360; no new colour
    expectation: the video path was proven by the 3-desktop pass."""

    def debug_contains(*needles):
        def assertion(root):
            text = root.property("debugInfo") or ""
            return all(needle in text for needle in needles)

        return assertion

    return [
        ("sheet=1", debug_contains("sheet=1")),
        ("tick=180.0", debug_contains("tick=180.0")),
        ("n=2/3", debug_contains("n=2/3")),
        ("lim=none", debug_contains("lim=none")),
        ("v=320", debug_contains("v=320")),
        (
            "no sheet=0",
            lambda root: "sheet=0" not in (root.property("debugInfo") or ""),
        ),
    ]


def run_child(import_root, clip, desktop_count):
    """Single scenario inside its own process (fresh QGuiApplication + engine).

    One scenario per process is deliberate: a second QGuiApplication.exec()
    after the first application.exit() never returned (the sheet pass hung with
    the clip already decoded), and a brand-new Qt event loop per pass is what
    the render test isolates anyway. Return 0 == the scenario passed.
    """
    application = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    if application.platformName() in ("offscreen", "minimal"):
        print(
            "check-video-dome: skipped (needs a real platform; QtQuick3D does not render offscreen)"
        )
        return 0
    if desktop_count == 3:
        # A: polygon; the pixel proof of the dome.
        expectations, check_video = [], True
    else:
        # B: sheet; property assertions through the DebugOverlay, no grab.
        expectations, check_video = sheet_assertions(), False
    code = run_scenario(
        application, import_root, clip, desktop_count, expectations, check_video
    )
    print(f"check-video-dome [n={desktop_count}]:", "OK" if code == 0 else "FAIL")
    return 0 if code == 0 else 1


def main(argv):
    # Child mode: run one scenario, invoked by the parent loop below.
    # argv = [script, clip, import_root, "--scenario", count].
    if "--scenario" in argv:
        i = argv.index("--scenario")
        return run_child(Path(argv[2]), Path(argv[1]), int(argv[i + 1]))

    clip = Path(argv[1]) if len(argv) > 1 else DEFAULT_CLIP
    if not clip.is_file():
        print(f"check-video-dome: skipped (no clip at {clip})")
        return 0

    # Qt Quick 3D does not render on the offscreen plugin and QGuiApplication
    # aborts with no platform at all, so bail out before creating it.
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        print("check-video-dome: skipped (no display; QtQuick3D needs a real platform)")
        return 0

    with tempfile.TemporaryDirectory() as temporary:
        import_root = write_stub_module(temporary)
        for desktop_count in (3, 2):
            # A fresh process per scenario (see run_child); the child reuses
            # this stub directory before the context manager removes it.
            # The output is captured so the QML-error signatures can be
            # scanned here (a handler inside the child deadlocks).
            result = subprocess.run(
                [
                    sys.executable,
                    "-u",
                    str(Path(__file__).resolve()),
                    str(clip),
                    str(import_root),
                    "--scenario",
                    str(desktop_count),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            print(result.stdout, end="")
            qml_errors = [
                line
                for line in (result.stdout + result.stderr).splitlines()
                if any(signature in line for signature in QML_ERROR_SIGNATURES)
                # The child's own FAIL lines already report the error; do not
                # print them twice through the parent's re-scan.
                and "qml error:" not in line
            ]
            for message in qml_errors:
                print(f"FAIL [n={desktop_count}] qml error: {message}")
            if result.returncode != 0:
                if result.stderr:
                    print(result.stderr, end="", file=sys.stderr)
                print(
                    f"check-video-dome [n={desktop_count}]:",
                    "FAIL",
                )
                return 1
            if qml_errors:
                print(f"check-video-dome [n={desktop_count}]: FAIL (qml errors)")
                return 1
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
