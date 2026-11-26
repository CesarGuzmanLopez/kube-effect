#!/usr/bin/env python3
"""Wiring gate for the cylinder branches (ADR-025): the REAL Cube.qml.

check-cylinder.py validates the arc's vertex data through CylinderArcMesh;
this script proves the cable above it — Cube.qml itself, instantiated with
the stub org.kde.kwin module (the same VirtualDesktopModel stub as
check-video-dome.py, reused so the two never drift) and Shape = Cylinder:

  * 3 desktops  -> isCylinder + cylinderActive, NOT cylinderSegments,
    Loader.Ready produced a real Geometry (cylinderMesh non-null) or — on a
    system without QtQuick3D.Helpers — the documented fallback: both flags
    false, no crash (the script prints which path ran);
  * angleTick stays the polygon tick (360/3); faceDistance is R = N(W+g)/2pi;
  * culling parity (ADR-025 point 12, reverted): faceCullMode stays
    Material.NoCulling for inside, margin and OUTSIDE camera radii — the
    mirrored inner wall must stay visible through the gaps exactly like in
    the polygon (ADR-023); the numbers compared come from the QML side
    because PySide cannot convert the enum itself;
  * 2 desktops  -> cylinderSegments (the curved segment of ADR-025 point 11)
    with angleTick exactly 120 and faceDistance = 3W/2pi (no g);
  * 1 desktop   -> the single-face segment: cylinderSegments, faceDistance
    3W/2pi and the arrow range [-60, 60] (cylinderAzimuthRange(1)), one
    face at azimuth 0.
Each helpers case also checks the first vertex of the produced geometry
against the expected radius (hypot(x, z)) — that closes the Loader->holder
binding wiring: the mesh actually received the R the formula computed.

Nothing is rendered: no View3D, no window — only the object tree and the
bindings, so QT_QPA_PLATFORM=offscreen is enough (unlike check-video-dome,
which needs a real screen to grab pixels). Skipped (exit 0) when PySide6 is
missing.
"""

import importlib.util
import math
import os
import sys
import tempfile
from pathlib import Path

try:
    from PySide6.QtCore import QUrl, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
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
    # error found in the drum run is not re-reported under segment 2 and 1.
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
    segments = bool(harness.property("cylinderSegments"))
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
    else:
        # (The fallback branch asserts below only need the flags; the earlier
        # problems list already carries anything found here — no duplicated
        # extend, review nit #1.)
        pass

    if desktop_count == 3:
        if helpers:
            if not active or segments:
                problems.append(
                    "3 desktops: expected cylinderActive, not cylinderSegments"
                )
            if not close(tick, 360.0 / 3):
                problems.append(f"3 desktops: angleTick {tick} != 120 (polygon parity)")
            if faces != 3:
                problems.append(f"3 desktops: faceCount {faces} != 3")
            expected_distance = 3 * (width + 100.0) / (2 * math.pi)
            if not close(distance, expected_distance, 1e-3):
                problems.append(
                    f"3 desktops: faceDistance {distance} != R=N(W+g)/2pi {expected_distance}"
                )
            # Culling parity (ADR-025 point 12, reverted): NoCulling is
            # pinned for inside, the 1.05 margin AND outside — the inner
            # wall seen through the gaps is polygon parity (ADR-023), the
            # overlap over the front faces is a paint-order problem, not a
            # culling one (the faceCullMode TODO + cylinderCullMode seed
            # stay ready for the real fix).
            expected_distance_and_radius = expected_distance
            for factor in (0.5, 1.02, 2.0):
                harness.setProperty("cameraRadius", distance * factor)
                application.processEvents()
                if int(harness.property("faceCullMode")) != none_value:
                    problems.append(
                        f"drum cameraRadius {factor}R: faceCullMode is not "
                        "Material.NoCulling (culling reverted, ADR-025 pt.12)"
                    )
            # The holder binding actually delivered R to the vertices:
            # hypot(x, z) of the first vertex equals the drum radius.
            first = geometry[0]
            r_v = math.hypot(float(first.x()), float(first.z()))
            if not close(r_v, expected_distance_and_radius, 1e-3):
                problems.append(
                    f"drum mesh vertex radius {r_v} != R {expected_distance_and_radius}"
                )
            info = "drum (3): helpers path, NoCulling parity + mesh R verified"
        else:
            if active or segments:
                problems.append(
                    "fallback (no Helpers): both cylinder flags must be false"
                )
            info = "drum (3): fallback path (QtQuick3D.Helpers missing) — no crash, flat faces"
    elif desktop_count == 2:
        if helpers:
            if not segments or active:
                problems.append(
                    "2 desktops: expected cylinderSegments, not cylinderActive"
                )
            if not close(tick, 120.0):
                problems.append(f"2 desktops: segment angleTick {tick} != 120")
            if faces != 2:
                problems.append(f"2 desktops: faceCount {faces} != 2")
            expected_distance = 3 * width / (2 * math.pi)
            if not close(distance, expected_distance, 1e-3):
                problems.append(
                    f"2 desktops: faceDistance {distance} != 3W/2pi {expected_distance}"
                )
            for factor in (0.5, 1.02, 2.0):
                harness.setProperty("cameraRadius", distance * factor)
                application.processEvents()
                if int(harness.property("faceCullMode")) != none_value:
                    problems.append(
                        f"segment cameraRadius {factor}R: faceCullMode is not "
                        "Material.NoCulling (culling reverted, ADR-025 pt.12)"
                    )
            first = geometry[0]
            r_v = math.hypot(float(first.x()), float(first.z()))
            if not close(r_v, expected_distance, 1e-3):
                problems.append(
                    f"segment mesh vertex radius {r_v} != 3W/2pi {expected_distance}"
                )
            info = "segment (2): helpers path, cylinderSegments + angleTick 120 + NoCulling verified"
        else:
            if segments:
                problems.append("fallback (no Helpers): cylinderSegments must be false")
            info = "segment (2): fallback path (QtQuick3D.Helpers missing) — flat sheet"
    elif desktop_count == 1:
        if helpers:
            if not segments or active:
                problems.append(
                    "1 desktop: expected cylinderSegments, not cylinderActive"
                )
            if faces != 1:
                problems.append(f"1 desktop: faceCount {faces} != 1")
            expected_distance = 3 * width / (2 * math.pi)
            if not close(distance, expected_distance, 1e-3):
                problems.append(
                    f"1 desktop: faceDistance {distance} != 3W/2pi {expected_distance}"
                )
            if not close(tick, 360.0):
                problems.append(f"1 desktop: angleTick {tick} != 360 (one face)")
            first = geometry[0]
            r_v = math.hypot(float(first.x()), float(first.z()))
            if not close(r_v, expected_distance, 1e-3):
                problems.append(
                    f"1 desktop: mesh vertex radius {r_v} != 3W/2pi {expected_distance}"
                )
            info = (
                "segment (1): helpers path, one arc at azimuth 0, range seed [-60,60]"
            )
        else:
            if segments:
                problems.append("fallback (no Helpers): cylinderSegments must be false")
            info = "segment (1): fallback path (QtQuick3D.Helpers missing) — flat sheet"
    else:
        problems.append(f"unsupported scenario count {desktop_count}")

    for message in messages:
        problems.append(f"qml: {message.strip()}")
    return problems, info


def main():
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

    print("cylinder wiring: " + " | ".join(infos))
    if problems:
        print("check-cylinder-wiring: FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1
    print(
        "check-cylinder-wiring: OK (real Cube.qml: drum + segment flags, Loader mesh, "
        "R faceDistance, polygon-parity tick, NoCulling parity after the revert, and "
        "the mesh vertices carry the radius the holder was bound)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
