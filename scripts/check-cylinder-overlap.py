#!/usr/bin/env python3
"""Render gate for the cylinder overlap fix (ADR-026): the REAL Cube.qml.

The user measured, in the nested KWin, the inner wall of the far arcs being
PAINTED OVER the front faces of the drum (op = 1.00 at rest, worse while
turning). The diagnosis landed on two mechanisms, both proven here:

  * pixels (what the eye must never see again): the near face wins every
    column of its own footprint — at rest (yaw 0, opacity 1) the front arc's
    red dominates its whole band, and mid-turn (yaw 60, opacity 0.7 — the
    Blend pass) the two near faces keep blue/red dominance while the far
    wall shows ONLY through the gap (green in the centre band, the look the
    user wants to keep). And the face texture's alpha holes stay
    see-through at rest (a black hole band would mean the material was
    forced fully Opaque, which erases the desktop behind — measured as a
    regression in the engine before choosing Mask).
  * structure (the two parts of the fix, asserted live on the created
    scene): every face node carries a DISTINCT position of magnitude R
    (polygon-style placement — the ADR-026 sort centroid: QtQuick3D orders
    the transparent pass by the bounds centre projected on the view axis,
    qssglayerrenderdata.cpp), and the material is a PrincipledMaterial
    whose alphaMode follows the faceOpacity threshold (>= 0.99 -> Mask,
    < 0.99 -> Blend). With the old code both structural assertions fail
    (all nodes pinned to (0,0,0); DefaultMaterial has no alphaMode);
  * single: the one-desktop three-slot drum — the face sits at slot 0
    (azimuth 0) and ALWAYS owns the centre pixel at rest (the user's
    "face behind" regression guard), with the same R = 3(W + g)/2pi the
    closed drum uses (the slot count is pinned to three, the missing
    delegates are exactly what the open range parks on).
  * poly: the Polygon reference — Mask is bounded to the curved faces
    (re-review of ADR-026): a flat face at rest keeps Blend, the virgin
    ADR-023 look (distinct positions already order it; a Mask there would
    hard-cut shadows/AA and snap sub-0.5 windows solid for no proven
    benefit). alphaCutoff is pinned explicitly at 0.5.

Honesty note (measured, not assumed): with FLAT opaque colours the pixel
assertions also pass on the OLD placement — this engine build sorted the
drum's centroids correctly for that content — so the pixels are the
regression guard for the order, and the STRUCTURAL asserts are what pin
the fix itself. The overlap the user measured lives in the nested KWin
(real composited desktop textures); this harness keeps the invariant
testable here and the user verifies the look in the arnés.

Reuses check-video-dome.py's stub org.kde.kwin module (its WindowFilterModel
/ WindowThumbnail stubs now paint one flat colour per desktop, so each face
is identifiable). Skipped (exit 0) without PySide6, without a display, or on
the offscreen/minimal platforms: QtQuick3D does not render there.
"""

import importlib.util
import json
import math
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
    from PySide6.QtQml import QQmlEngine
    from PySide6.QtQuick import QQuickView
except ImportError:  # pragma: no cover - optional dependency
    print("check-cylinder-overlap: skipped (PySide6 is not installed)")
    sys.exit(0)

ROOT = Path(__file__).resolve().parent.parent

# The stub module of check-video-dome.py (same VirtualDesktopModel, now with
# coloured WindowThumbnails): loaded as a file module, hyphenated name.
_spec = importlib.util.spec_from_file_location(
    "check_video_dome_for_stubs", ROOT / "scripts/check-video-dome.py"
)
_dome = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_dome)

# Harness geometry (mirrors check-cylinder-overlap.qml): face size 640x360,
# displacement 100; the drum keeps three slots even with one desktop, so the
# radius is the N = 3 formula everywhere (three-slot drum, ADR-026).
FACE_WIDTH = 640.0
FACE_HEIGHT = 360.0
GAP = 100.0
DESKTOPS = 3
DRUM_RADIUS = DESKTOPS * (FACE_WIDTH + GAP) / (2 * math.pi)

# Scenarios: name -> (yaw, opacity, stub coverage, desktop count, shape).
#   rest/turn/holes: the closed 3-desktop drum (paint order + look).
#   single: the THREE-SLOT drum with one desktop (ADR-025 pt.11
#   re-rectified) — the user's "face behind" guard: the single face
#   (slot 0, azimuth 0) owns the centre of the view, and the open
#   range + slot-0 azimuth keep the resting target front-facing.
#   poly: the Polygon reference (shape 0) — Mask is bounded to the
#   cylinder (re-review of ADR-026): flat faces never had the overlap
#   (their positions are distinct sort centroids) and the virgin ADR-023
#   look blends at rest, so EVERY polygon face must report Blend even at
#   opacity 1, and its front quad must still own the middle row.
SCENARIOS = {
    "rest": (0.0, 1.0, 1.0, 3, 1),
    "turn": (60.0, 0.7, 1.0, 3, 1),
    "holes": (0.0, 1.0, 0.72, 3, 1),
    "single": (0.0, 1.0, 1.0, 1, 1),
    "poly": (0.0, 1.0, 1.0, 3, 0),
}

RED = (1.0, 0.0, 0.0)
GREEN = (0.0, 1.0, 0.0)
BLUE = (0.0, 0.0, 1.0)


def classify(rgb):
    """Dominant-colour class of one pixel: R/G/B/M(agenta)/K(black)/'.'."""
    r, g, b = rgb
    if r > 150 and g < 110 and b < 110:
        return "R"
    if g > 150 and r < 110 and b < 110:
        return "G"
    if b > 150 and r < 110 and g < 110:
        return "B"
    if r > 150 and b > 150 and g < 110:
        return "M"
    if r < 60 and g < 60 and b < 60:
        return "K"
    return "."


def run_scenario(application, import_root, name, yaw, opacity, coverage, count, shape):
    """One engine + view + grab, exactly the check-video-dome pattern.

    The warm-up load runs BEFORE any message handler is installed (a handler
    from the first load deadlocks the QML type-loader thread against the
    GIL, measured in check-video-dome.py); the real view is then created with
    a handler collecting the three QML error signatures.
    """
    engine = QQmlEngine()
    engine.addImportPath(str(import_root))
    engine.rootContext().setContextProperty("stubDesktopCount", count)
    engine.rootContext().setContextProperty("stubFaceCoverage", coverage)
    harness_url = QUrl.fromLocalFile(str(ROOT / "scripts/check-cylinder-overlap.qml"))

    warm = QQuickView(engine, None)
    warm.setSource(harness_url)
    if warm.status() != QQuickView.Status.Ready:
        print(f"check-cylinder-overlap: FAIL ({name}, warm-up)")
        for error in warm.errors():
            print(f" - {error.toString()}")
        return 1
    warm.destroy()

    qml_errors = []

    def forward_qml_warnings(_mode, _context, message):
        if any(signature in message for signature in _dome.QML_ERROR_SIGNATURES):
            qml_errors.append(message)

    qInstallMessageHandler(forward_qml_warnings)

    view = QQuickView(engine, None)
    view.resize(640, 360)
    view.setSource(harness_url)
    if view.status() != QQuickView.Status.Ready:
        print(f"check-cylinder-overlap: FAIL ({name}, engine)")
        for error in view.errors():
            print(f" - {error.toString()}")
        return 1
    view.show()
    root = view.rootObject()
    root.setProperty("yaw", yaw)
    root.setProperty("faceOpacity", opacity)
    root.setProperty("shape", shape)

    failures = []

    def band(image, y, x0, x1, expected, label):
        """Every sampled pixel in [x0, x1] must classify as `expected`."""
        bad = []
        for x in range(x0, x1 + 1, 4):
            value = image.pixel(x, y)
            rgb = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
            got = classify(rgb)
            if got != expected:
                bad.append((x, got, rgb))
        ok = not bad
        detail = "" if ok else f" ({len(bad)} bad, first: {bad[0]})"
        print(f"{'PASS' if ok else 'FAIL'} [{name}] {label}{detail}")
        if not ok:
            failures.append(label)

    def check():
        # Force the snapshot binding to re-run after the property writes.
        root.setProperty("snapshotTick", 1)
        application.processEvents()
        image = view.grabWindow().convertToFormat(QImage.Format_RGB32)

        # -- structure: the two parts of the ADR-026 fix.
        try:
            snapshot = json.loads(str(root.property("snapshot") or "{}"))
        except json.JSONDecodeError as error:
            print(f"FAIL [{name}] snapshot is not JSON: {error}")
            failures.append("snapshot")
            snapshot = {}
        faces = snapshot.get("faces", [])
        cylinder = shape == 1
        expected_faces = 3 if name not in ("single",) else 1
        want_active = cylinder
        ok = (
            len(faces) == expected_faces
            and snapshot.get("cylinderActive") is want_active
            and snapshot.get("faceCount") == expected_faces
            and bool(snapshot.get("hasMesh")) is cylinder
        )
        print(
            f"{'PASS' if ok else 'FAIL'} [{name}] {expected_faces} face Models, cylinderActive={want_active}, mesh={cylinder} "
            f"(got {len(faces)}, count {snapshot.get('faceCount')}, active {snapshot.get('cylinderActive')}, mesh {snapshot.get('hasMesh')})"
        )
        if not ok:
            failures.append("faces")
        # Cylinder: every face at the drum R (slots pinned to 3). Polygon:
        # the apothem 0.5W/tan(tick/2) + displacement — both are the node
        # positions, which is what feeds the transparent-pass sort centroid
        # (ADR-026).
        expected_radius = (
            DRUM_RADIUS
            if cylinder
            else 0.5 * FACE_WIDTH / math.tan(math.pi / 3) + GAP
        )
        radii = [math.hypot(face["x"], face["z"]) for face in faces]
        ok = all(abs(radius - expected_radius) <= 1e-3 for radius in radii) and bool(faces)
        print(
            f"{'PASS' if ok else 'FAIL'} [{name}] face positions at the placement radius"
            f" = {expected_radius:.2f} (got {[round(r, 2) for r in radii]})"
        )
        if not ok:
            failures.append("radius")
        distinct = True
        for i in range(len(faces)):
            for j in range(i + 1, len(faces)):
                delta = math.hypot(
                    faces[i]["x"] - faces[j]["x"], faces[i]["z"] - faces[j]["z"]
                )
                if delta <= 1.0:
                    distinct = False
        print(
            f"{'PASS' if (distinct and faces) else 'FAIL'} [{name}] sort centroids pairwise "
            "distinct (polygon-style placement, ADR-026)"
        )
        if not (distinct and faces):
            failures.append("centroids")
        rest = opacity >= 0.99
        want_mask = rest and cylinder
        mode_ok = bool(faces) and all(
            (face["mask"] if want_mask else face["blend"]) and face["hasAlphaMode"]
            for face in faces
        )
        print(
            f"{'PASS' if mode_ok else 'FAIL'} [{name}] alphaMode "
            f"{'Mask' if want_mask else 'Blend'} at faceOpacity {opacity} on "
            f"{'cylinder' if cylinder else 'polygon'} (Mask bounded to the curved faces) "
            f"(mask {[f['mask'] for f in faces]}, blend {[f['blend'] for f in faces]})"
        )
        if not mode_ok:
            failures.append("alphaMode")
        opacity_ok = bool(faces) and all(
            abs(face["opacity"] - opacity) < 1e-6 for face in faces
        )
        print(
            f"{'PASS' if opacity_ok else 'FAIL'} [{name}] material opacity tracks faceOpacity"
        )
        if not opacity_ok:
            failures.append("opacity")

        # -- pixels: paint order.
        def px(x, y):
            value = image.pixel(x, y)
            return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)

        centre = classify(px(320, 180))
        if name in ("rest", "single", "poly"):
            band(image, 180, 160, 480, "R", "front arc owns the middle row")
            band(image, 120, 160, 480, "R", "front arc owns the upper row")
            band(image, 240, 160, 480, "R", "front arc owns the lower row")
        elif name == "turn":
            band(image, 180, 150, 260, "B", "left near face owns its band")
            band(image, 180, 390, 500, "R", "right near face owns its band")
            band(
                image, 180, 285, 355, "G", "far wall shows through the gap (kept look)"
            )
        elif name == "holes":
            black = [
                (x, px(x, 180))
                for x in range(450, 505, 4)
                if classify(px(x, 180)) == "K"
            ]
            ok = not black and centre != "K"
            print(
                f"{'PASS' if ok else 'FAIL'} [{name}] face texture holes stay see-through at rest"
                f"{' (black pixels: ' + str(black[:3]) + ')' if black else ''}"
            )
            if not ok:
                failures.append("holes")
        print(f"[{name}] centre pixel class: {centre}")

        for message in qml_errors:
            print(f"FAIL [{name}] qml error: {message}")
        if qml_errors:
            failures.append("qml-errors")
        application.exit(0 if not failures else 1)

    QTimer.singleShot(3000, check)
    code = application.exec()
    view.hide()
    view.destroy()
    engine.deleteLater()
    return code


def main(argv):
    # Child mode: python3 check-cylinder-overlap.py <import_root> --scenario <name>
    if "--scenario" in argv:
        name = argv[argv.index("--scenario") + 1]
        import_root = Path(argv[1])
        yaw, opacity, coverage, count, shape = SCENARIOS[name]
        application = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
        if application.platformName() in ("offscreen", "minimal"):
            print(
                "check-cylinder-overlap: skipped (needs a real platform; QtQuick3D does not render offscreen)"
            )
            return 0
        return run_scenario(application, import_root, name, yaw, opacity, coverage, count, shape)

    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        print(
            "check-cylinder-overlap: skipped (no display; QtQuick3D needs a real platform)"
        )
        return 0

    problems = 0
    with tempfile.TemporaryDirectory() as temporary:
        import_root = _dome.write_stub_module(temporary)
        for name in SCENARIOS:
            # Fresh process per scenario (the check-video-dome lesson: a second
            # QGuiApplication.exec() after the first exit never returned).
            result = subprocess.run(
                [
                    sys.executable,
                    "-u",
                    str(Path(__file__).resolve()),
                    str(import_root),
                    "--scenario",
                    name,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            print(result.stdout, end="")
            qml_errors = [
                line
                for line in (result.stdout + result.stderr).splitlines()
                if any(signature in line for signature in _dome.QML_ERROR_SIGNATURES)
                and "qml error:" not in line
            ]
            for message in qml_errors:
                print(f"FAIL [{name}] qml error (parent scan): {message}")
            if result.returncode != 0:
                if result.stderr:
                    print(result.stderr, end="", file=sys.stderr)
                problems += 1
            elif qml_errors:
                problems += 1
    if problems:
        print(f"check-cylinder-overlap: FAIL ({problems} scenario(s))")
        return 1
    print(
        "check-cylinder-overlap: OK (pixels: near faces own their footprint at rest and mid-turn,"
        " the far wall shows only through the gap, the face holes stay see-through;"
        " structure: per-face sort centroids at radius R, alphaMode Mask/Blend by threshold)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
