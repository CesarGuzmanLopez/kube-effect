#!/usr/bin/env python3
"""Wiring gate for the cylinder branches (ADR-025/ADR-026): the REAL Cube.qml.

check-cylinder.py validates the arc's vertex data through CylinderArcMesh;
this script proves the cable above it — Cube.qml itself, instantiated with
the stub org.kde.kwin module (the same VirtualDesktopModel stub as
check-video-dome.py, reused so the two never drift) and Shape = Cylinder:

  * 3 desktops  -> isCylinder + cylinderActive, Loader.Ready produced a
    real Geometry (cylinderMesh non-null) or — on a system without
    QtQuick3D.Helpers — the documented fallback: flags false, no crash
    (the script prints which path ran);
  * angleTick stays the polygon tick (360/3); faceDistance is R = N(W+g)/2pi;
  * the turn range (Constants.azimuthRangeFor via the harness, ADR-026) is
    OPEN [null, null] at EVERY cylinder count with the mesh;
  * culling parity (ADR-025 point 12, reverted): faceCullMode stays
    Material.NoCulling for inside, margin and OUTSIDE camera radii — the
    mirrored inner wall must stay visible through the gaps exactly like in
    the polygon (ADR-023); the numbers compared come from the QML side
    because PySide cannot convert the enum itself;
  * 2 desktops  -> the THREE-SLOT drum (ADR-025 point 11, re-rectified: the
    capped [-60, 180] band made jumps and felt choppy): cylinderActive,
    angleTick exactly 120, faceDistance = 3(W + g)/2pi — the user gap
    APPLIES now (the harness sets faceDisplacement = 100) — two faces in
    slots 0 and 1, slot 2 has no delegate;
  * 1 desktop   -> the same three-slot drum: cylinderActive, angleTick 120,
    faceDistance = 3(W + g)/2pi, one face at azimuth 0 (slot 0: ALWAYS
    front-facing when the effect opens — targetAzimuth is verbatim on the
    open range) and two empty slots showing the hull.
Each helpers case also checks the first vertex of the produced geometry
against the expected radius AROUND THE NODE-LOCAL AXIS (ADR-026): the arc
wraps (0, 0, -R) in its own frame now (the Model carries the radius as its
position, so every face gets a distinct transparent-pass sort centroid),
so hypot(x, z + R) must equal R — that closes the Loader->holder binding
wiring: the mesh actually received the R the formula computed.

Each helpers case ALSO checks the radius CHAIN the camera measures against
(ADR-026b, the v=4 regression the user measured with the DebugOverlay):
viewRadius === safeViewRadius === cylinderRadius === faceDistance === R at
ANY count (3, 2 or 1) — reading viewRadius through the sheet chain
(faceDistance -> sheetGap -> viewRadius) froze it at max(1, 0.005*R) ~ 4
when the arc Loader mounted mid-evaluation, and the wheel cap 8*4 = 32
trapped the camera INSIDE the drum. An explicit "viewRadius is not the
sheetGap" assert pins the structural cause (>100 px away from the gap),
and close/distant (mirroring ScreenView's formulas with the schema's
DistanceFactor) must both exceed R: with 1-2 desktops the camera states
never sit inside the drum either.

Finally the FLIP scenario (child process, the real ScreenView.qml loaded
offscreen with the stub kwin module, no window): 2 desktops + Shape =
Polygon (the flat sheet, viewRadius = half a face) flipped to Shape =
Cylinder mid-session — the exact sequence that froze viewRadius before
the fix. After settling, the DebugOverlay line itself is parsed and must
read v == d == R (and lim=none, slots=2/3): the frozen v=4 cannot survive
the binding-cycle-free branch order. This is the regression gate for the
root cause of ADR-026b; with the old Cube.qml it fails (measured before
the fix: 'Binding loop detected for property "viewRadius"', v=4).

Nothing is rendered: no View3D, no window — only the object tree and the
bindings, so QT_QPA_PLATFORM=offscreen is enough (unlike check-video-dome,
which needs a real screen to grab pixels). Skipped (exit 0) when PySide6 is
missing.
"""

import importlib.util
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PySide6.QtCore import QEventLoop, QTimer, QUrl, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine, QQmlPropertyMap
except ImportError:  # pragma: no cover - optional dependency
    print("check-cylinder-wiring: skipped (PySide6 is not installed)")
    sys.exit(0)

ROOT = Path(__file__).resolve().parent.parent

# Reuse the stub org.kde.kwin module of check-video-dome.py: the same
# VirtualDesktopModel (rows with a real desktop QObject), WindowFilterModel,
# WindowThumbnail and Workspace singleton. Loaded as a file module because
# the name contains hyphens.
_spec = importlib.util.spec_from_file_location(
    "check_video_dome_for_stubs", ROOT / "scripts/check-video-dome.py"
)
_dome = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_dome)

messages: list[str] = []


def collect_errors(_mode, _context, message):
    if any(signature in message for signature in _dome.QML_ERROR_SIGNATURES):
        messages.append(message)


def close(actual, expected, tolerance=1e-6):
    return abs(float(actual) - float(expected)) <= tolerance


def run_scenario(application, import_root, desktop_count):
    """Create Cube.qml with the stub model at the given desktop count.

    Returns (problems, info): problems is a list of failure strings (empty
    = the scenario passed), info describes the exercised Helpers path.
    """
    problems: list[str] = []
    # The handler is module-level: drop the previous scenario's messages so an
    # error found in the drum run is not re-reported under drum 2 and 1.
    messages.clear()
    engine = QQmlEngine()
    engine.addImportPath(str(import_root))
    engine.rootContext().setContextProperty("stubDesktopCount", desktop_count)
    component = QQmlComponent(engine)
    component.loadUrl(
        QUrl.fromLocalFile(str(ROOT / "scripts/check-cylinder-wiring.qml"))
    )
    if component.isError():
        for error in component.errors():
            problems.append(f"load: {error.toString()}")
        return problems, "load-error"

    harness = component.create()
    if harness is None:
        return [f"create: {component.errorString()}"], "create-error"
    application.processEvents()  # Loader + Repeater3D settle synchronously

    width = float(harness.property("faceSizeWidth"))
    is_cylinder = bool(harness.property("isCylinder"))
    active = bool(harness.property("cylinderActive"))
    mesh = harness.property("cylinderMesh")
    faces = int(harness.property("faceCount"))
    tick = float(harness.property("angleTick"))
    distance = float(harness.property("faceDistance"))
    cull_mode = int(harness.property("faceCullMode"))
    none_value = int(harness.property("noneCullValue"))
    # backCullValue is exported by the harness: the pinned property must not
    # equal it anywhere — read and assert it (a regressed cull pin would
    # otherwise pass the != none_value checks by coincidence of value).
    back_value = int(harness.property("backCullValue"))
    range_json = str(harness.property("cylRangeJson"))

    # faceCullMode is pinned to Material.NoCulling in the runtime (ADR-025
    # point 12 reverted): check the initial value before the sweeps.
    if cull_mode != none_value:
        problems.append(
            "initial faceCullMode is not Material.NoCulling (cameraRadius 0)"
        )
    if cull_mode == back_value:
        problems.append(
            "initial faceCullMode is Material.BackFaceCulling (the culling revert regressed)"
        )

    if not is_cylinder:
        problems.append(
            f"Shape=Cylinder did not reach Cube.isCylinder (count={desktop_count})"
        )

    helpers = mesh is not None
    if helpers:
        # Geometry object: the Loader reached Ready and item.mesh exists.
        geometry = mesh.property("positions")
        if geometry is None or len(geometry) == 0:
            problems.append(
                "cylinderMesh exists but has no positions (Loader half-ready?)"
            )
        # Radius chain (ADR-026b, the v=4 regression the user measured): with
        # the drum in effect viewRadius must BE faceDistance must BE R at ANY
        # count (3, 2 or 1) — reading it through the sheet chain (faceDistance
        # -> sheetGap -> viewRadius) froze it at max(1, 0.005*R) ~ 4 when the
        # Loader mounted mid-evaluation, so the wheel cap became 8*4 = 32 and
        # distant 4*1.75 + faceFit: the camera inside the drum (r=32, r=28).
        expected_distance_all = 3 * (width + 100.0) / (2 * math.pi)
        view_radius = float(harness.property("viewRadius"))
        sheet_gap = float(harness.property("sheetGap"))
        safe_view_radius = float(harness.property("safeViewRadius"))
        cylinder_radius = float(harness.property("cylinderRadiusValue"))
        height = float(harness.property("faceSizeHeight"))
        if not close(view_radius, distance, 1e-6):
            problems.append(
                f"count {desktop_count}: viewRadius {view_radius} != faceDistance {distance} (the sheet branch leaked into the drum)"
            )
        if not close(view_radius, cylinder_radius, 1e-6) or not close(
            cylinder_radius, expected_distance_all, 1e-6
        ):
            problems.append(
                f"count {desktop_count}: viewRadius/cylinderRadius {view_radius}/{cylinder_radius} != R {expected_distance_all}"
            )
        if not close(safe_view_radius, view_radius, 1e-6):
            problems.append(
                f"count {desktop_count}: safeViewRadius {safe_view_radius} != viewRadius {view_radius}"
            )
        # Structural guard (the brief's literal assert): with cylinderActive,
        # viewRadius may NEVER equal the sheet gap max(1, 0.005*R); with this
        # harness's R ~ 1272 the two differ by ~1266 px, so the frozen-gap
        # regression (viewRadius stuck at sheetGap ~ 4, R printed 776 beside
        # v=4 in the user's overlay) cannot pass by coincidence (>100 px rule).
        if abs(view_radius - sheet_gap) <= 100.0:
            problems.append(
                f"count {desktop_count}: viewRadius {view_radius} sits on the sheetGap branch (sheetGap {sheet_gap} = max(1, 0.005*R)) — the ADR-026b binding-cycle regression"
            )
        # close/distant sit OUTSIDE the drum: the formulas mirror ScreenView's
        # closeRadius/distantRadius (fov 60 is the measured PerspectiveCamera
        # default, DistanceFactor the schema default 1.75); with
        # safeViewRadius === R pinned above they can no longer collapse
        # towards the axis.
        face_fit = 0.5 * height / math.tan(0.5 * 60.0 * math.pi / 180.0)
        close_radius = distance + face_fit
        distant_radius = safe_view_radius * 1.75 + face_fit
        if (
            close_radius <= expected_distance_all
            or distant_radius <= expected_distance_all
        ):
            problems.append(
                f"count {desktop_count}: close {close_radius} / distant {distant_radius} must both exceed R {expected_distance_all} (camera outside the drum)"
            )

    if desktop_count == 3:
        if helpers:
            if not active:
                problems.append("3 desktops: cylinderActive must be true with the mesh")
            if not close(tick, 360.0 / 3):
                problems.append(f"3 desktops: angleTick {tick} != 120 (polygon parity)")
            if faces != 3:
                problems.append(f"3 desktops: faceCount {faces} != 3")
            expected_distance = 3 * (width + 100.0) / (2 * math.pi)
            if not close(distance, expected_distance, 1e-3):
                problems.append(
                    f"3 desktops: faceDistance {distance} != R=N(W+g)/2pi {expected_distance}"
                )
            if range_json != "[null,null]":
                problems.append("3 desktops: the drum turn range must be OPEN")
            # Culling parity (ADR-025 point 12, reverted): NoCulling is
            # pinned for inside, the 1.05 margin AND outside — the inner
            # wall seen through the gaps is polygon parity (ADR-023), the
            # overlap over the front faces is a paint-order problem (fixed
            # by ADR-026; the faceCullMode note and the cylinderCullMode
            # seed stay as the documented alternative).
            for factor in (0.5, 1.02, 2.0):
                harness.setProperty("cameraRadius", distance * factor)
                application.processEvents()
                if int(harness.property("faceCullMode")) != none_value:
                    problems.append(
                        f"drum cameraRadius {factor}R: faceCullMode is not "
                        "Material.NoCulling (culling reverted, ADR-025 pt.12)"
                    )
            # The holder binding actually delivered R to the vertices:
            # hypot(x, z + R) of the first vertex (measured from the
            # node-local axis at (0, 0, -R), ADR-026) equals the drum radius.
            first = geometry[0]
            r_v = math.hypot(float(first.x()), float(first.z()) + expected_distance)
            if not close(r_v, expected_distance, 1e-3):
                problems.append(
                    f"drum mesh vertex radius {r_v} != R {expected_distance}"
                )
            info = "drum (3): helpers path, NoCulling parity + mesh R verified"
        else:
            if active:
                problems.append("fallback (no Helpers): cylinderActive must be false")
            info = "drum (3): fallback path (QtQuick3D.Helpers missing) — no crash, flat faces"
    elif desktop_count in (2, 1):
        # The three-slot drum (ADR-025 pt.11 re-rectified, ADR-026): 1-2
        # desktops keep the drum's formulas at N = 3 — the user gap g in R,
        # the slot grid tick 120, empty slots without delegates and the
        # OPEN turn range (no band caps, no asymmetric clamps: those made
        # jumps and felt choppy).
        label = f"three-slot drum ({desktop_count})"
        if helpers:
            if not active:
                problems.append(
                    f"{desktop_count} desktops: the three-slot drum must be cylinderActive (the band branch is retired)"
                )
            if not close(tick, 120.0):
                problems.append(
                    f"{desktop_count} desktops: slot-grid angleTick {tick} != 120"
                )
            if faces != desktop_count:
                problems.append(
                    f"{desktop_count} desktops: faceCount {faces} != {desktop_count}"
                )
            expected_distance = 3 * (width + 100.0) / (2 * math.pi)
            if not close(distance, expected_distance, 1e-3):
                problems.append(
                    f"{desktop_count} desktops: faceDistance {distance} != 3(W+g)/2pi {expected_distance}"
                )
            if range_json != "[null,null]":
                problems.append(
                    f"{desktop_count} desktops: the three-slot drum turn range must be OPEN (the band caps are retired)"
                )
            for factor in (0.5, 1.02, 2.0):
                harness.setProperty("cameraRadius", distance * factor)
                application.processEvents()
                if int(harness.property("faceCullMode")) != none_value:
                    problems.append(
                        f"{label} cameraRadius {factor}R: faceCullMode is not "
                        "Material.NoCulling (culling reverted, ADR-025 pt.12)"
                    )
            # The holder binding delivered the slot-drum R to the vertices.
            first = geometry[0]
            r_v = math.hypot(float(first.x()), float(first.z()) + expected_distance)
            if not close(r_v, expected_distance, 1e-3):
                problems.append(
                    f"{label}: mesh vertex radius {r_v} != 3(W+g)/2pi {expected_distance}"
                )
            if desktop_count == 1:
                # Slot 0 rule (the user's "face behind" guard, ADR-026): the
                # single face sits at faceAzimuth(0) = angleTick * 0 = 0 —
                # front-facing — and the open range leaves the state target
                # verbatim there; the empty slot 1 lives on the same grid at
                # 120 (a DRAG may park facing it, selection there is the
                # guarded no-op; the ARROWS hold the face, ADR-026b n=1
                # no-op). Both read from the live Cube.
                if not close(float(harness.property("slotZeroAzimuth")), 0.0):
                    problems.append(
                        "1 desktop: slot 0 must carry azimuth 0 (face always front)"
                    )
                if not close(float(harness.property("slotOneAzimuth")), 120.0):
                    problems.append(
                        "1 desktop: slot 1 of the grid must be at 120 (empty slot on the grid; a drag can park facing it, arrows never stop there, ADR-026b)"
                    )
            info = (
                f"{label}: helpers path, active + angleTick 120 + R=3(W+g)/2pi "
                "+ open range + NoCulling verified"
            )
        else:
            if active:
                problems.append("fallback (no Helpers): cylinderActive must be false")
            info = (
                f"{label}: fallback path (QtQuick3D.Helpers missing) — flat sheet "
                f"({'[-80,80]' if desktop_count == 1 else 'open'})"
            )
    else:
        problems.append(f"unsupported scenario count {desktop_count}")

    for message in messages:
        problems.append(f"qml: {message.strip()}")
    return problems, info


def flip_child(import_root: Path) -> int:
    """Regression lock for the frozen viewRadius (ADR-026b, bug A as the user
    measured it): run the REAL ScreenView.qml offscreen (bindings only — the
    View3D never needs to render for the object tree and its numbers to
    exist) with 2 desktops and Shape = Polygon, then flip Shape to Cylinder.

    The isSheet flip lands mid-evaluation (the arc Loader mounts and the
    drum chain activates in the same propagation): on the old Cube.qml the
    chain viewRadius -> faceDistance -> sheetGap -> viewRadius made Qt cut a
    BINDING LOOP and leave viewRadius frozen at sheetGap (~4) while
    faceDistance recovered to R — the engine logged 'Binding loop detected
    for property "viewRadius"' and the overlay showed d=776 v=4 r=786
    (distant = 4*1.75 + faceFit; the wheel cap became 8*4 = 32, the camera
    inside the drum). Reproduced offscreen exactly before the fix.

    With the fix the drum branch answers cylinderRadius first: the overlay
    must show v == d == R, sheet=0, lim=none, slots=2/3 — and NO binding-loop
    warning may appear (collected here, not part of the dome signatures).
    Runs in its own process: a fresh event loop per render-style scenario is
    the established pattern (check-video-dome), and the type cache is warmed
    BEFORE any message handler exists (the loader-thread/GIL deadlock).
    """
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    application = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])

    # A generic-KCM configuration (schema defaults for every key ScreenView
    # reads; the clip is irrelevant here — Background stays Color).
    config = QQmlPropertyMap()
    for key, value in {
        "CubeFaceDisplacement": 10.0,
        "DistanceFactor": 1.75,
        "Shape": 0,
        "DebugOverlay": True,
        "Background": 0,
        "BackgroundColor": "#270001",
        "BackgroundColor2": "#ff8a00",
        "BackgroundGradientType": 0,
        "BackgroundGradientStop": 50,
        "BackgroundGradientRotation": 0,
        "BackgroundImageLayout": 0,
        "BackgroundImageFit": 0,
        "BackgroundImageRotate": True,
        "SkyBox": "",
        "BackgroundVideo": "",
        "BorderActivate": "",
        "TouchBorderActivate": "",
        "CursorScreenOnly": False,
        "DimWhileRotating": False,
        "DimWhileRotatingAmount": 40,
        "MouseInvertedX": False,
        "MouseInvertedY": False,
        "FaceOpacity": 1.0,
        "FaceRotationOpacity": 0.7,
        "FaceFadeMs": 120,
    }.items():
        config.insert(key, value)
    # Keep both maps referenced for the whole scenario (a temporary is GC'd
    # and QML then reads an EMPTY configuration object — check-video-dome).
    effect = QQmlPropertyMap()
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
    engine.rootContext().setContextProperty("stubDesktopCount", 2)

    screen_view = ROOT / "package/contents/ui/ScreenView.qml"
    warm = QQmlComponent(engine)
    warm.loadUrl(QUrl.fromLocalFile(str(screen_view)))
    del warm  # types parsed on the calling thread, before any handler exists

    captured: list[str] = []

    def collect(_mode, _context, message):
        if (
            any(signature in message for signature in _dome.QML_ERROR_SIGNATURES)
            or "inding loop" in message
        ):
            captured.append(message)

    qInstallMessageHandler(collect)

    component = QQmlComponent(engine)
    component.loadUrl(QUrl.fromLocalFile(str(screen_view)))
    if component.isError():
        for error in component.errors():
            print(f" - flip load: {error.toString()}")
        return 1
    root = component.create()
    if root is None:
        print(f" - flip create: {component.errorString()}")
        return 1

    def pump(ms):
        loop = QEventLoop()
        QTimer.singleShot(ms, loop.quit)
        loop.exec()

    problems: list[str] = []
    pump(120)
    root.setProperty("width", 1616)
    root.setProperty("height", 900)
    pump(600)
    # The hot shape change with the cube open (what the KCM does): at 2
    # desktops this is the sequence that froze viewRadius on the old code.
    config.insert("Shape", 1)
    pump(900)
    info = str(root.property("debugInfo") or "")
    numbers = dict(re.findall(r"([A-Za-z_]+)=(-?\d+)", info))
    if numbers.get("sheet") != "0":
        problems.append(f"flip: the drum did not reach sheet=0 (overlay: {info!r})")
    if "lim=none" not in info:
        problems.append(
            "flip: the three-slot drum turn range must stay OPEN (lim=none)"
        )
    if "slots=2/3" not in info:
        problems.append("flip: the two-desktop drum must report slots=2/3")
    for field in ("d", "v", "R"):
        if numbers.get(field) is None:
            problems.append(f"flip: overlay field {field}= missing")
    if all(numbers.get(field) is not None for field in ("d", "v", "R")):
        d_value = int(numbers["d"])
        v_value = int(numbers["v"])
        r_value = int(numbers["R"])
        if not (v_value == d_value == r_value):
            problems.append(
                f"flip: viewRadius {v_value} != faceDistance {d_value} != R {r_value} (the v=4 freeze: camera trapped inside the drum)"
            )
    if captured:
        problems.extend(f"flip: qml: {message.strip()}" for message in captured)

    root.deleteLater()
    engine.deleteLater()
    if problems:
        print("check-cylinder-wiring [flip]: FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1
    print(
        "check-cylinder-wiring [flip]: OK (real ScreenView, hot Polygon->Cylinder "
        "flip at 2 desktops: v == d == R, sheet=0, lim=none, no binding-loop warning)"
    )
    return 0


def main():
    # Child mode: one flip scenario in a fresh process (argv =
    # [script, import_root, "--flip"]).
    if "--flip" in sys.argv:
        return flip_child(Path(sys.argv[1]))

    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    # Bindings run; nothing is rendered, so the software backend suffices.
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    qInstallMessageHandler(collect_errors)
    application = QGuiApplication(sys.argv)

    problems: list[str] = []
    infos: list[str] = []
    with tempfile.TemporaryDirectory(prefix="kube-stub-") as temporary:
        import_root = _dome.write_stub_module(temporary)
        for desktop_count in (3, 2, 1):
            scenario, info = run_scenario(application, import_root, desktop_count)
            infos.append(info)
            problems.extend(scenario)
        # The exact reproduction of the user's v=4 measurement (ADR-026b)
        # runs in its own process; the parent rescans its output as a net.
        flip = subprocess.run(
            [
                sys.executable,
                "-u",
                str(Path(__file__).resolve()),
                str(import_root),
                "--flip",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        print(flip.stdout, end="")
        flip_problems = [
            line
            for line in (flip.stdout + flip.stderr).splitlines()
            if (
                any(signature in line for signature in _dome.QML_ERROR_SIGNATURES)
                or "inding loop" in line
            )
            and "qml:" not in line
        ]
        for line in flip_problems:
            print(f" - flip qml: {line.strip()}")
        if flip.returncode != 0:
            problems.append(f"flip scenario exited {flip.returncode}")
        elif flip_problems:
            problems.append("flip scenario: QML error signatures in the child output")

    print("cylinder wiring: " + " | ".join(infos))
    if problems:
        print("check-cylinder-wiring: FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1
    print(
        "check-cylinder-wiring: OK (real Cube.qml: closed drum + three-slot drums, "
        "Loader mesh, R=3(W+g)/2pi faceDistance AND viewRadius with the sheetGap "
        "freeze guard, close/distant outside the drum, slot-grid tick 120, open "
        "turn ranges, NoCulling parity after the revert, the mesh vertices carry "
        "the radius the holder was bound, and the hot Polygon->Cylinder flip keeps "
        "v == d == R on the real ScreenView)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
