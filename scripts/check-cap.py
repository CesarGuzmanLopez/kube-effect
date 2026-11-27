#!/usr/bin/env python3
"""Geometry check of the REAL cap mesh (tapas, ADR-027 + amendment).

Boots CapMesh.qml — the same ProceduralMesh (QtQuick3D.Helpers) that
Cube.qml loads at runtime for both caps — in an offscreen QML engine (no
window, no GPU, no KWin: only vertex data is read back, never rendered)
and validates it with the pure contract in cap_contract.py (read its
docstring for the clauses: per-face prism invariant and corner bound, the
inscribed N-gon at d <= 0, the 2N face-corner ring with inside gap
chords at d > 0, disc radius/fan/UVs, the shared-mesh Cube pattern and
the empty-arrays degenerate contract).

--selftest (also served from cap_contract) validates the validator: the
classic breakages, the amendment's three regressions and the six direct
branch probes — see cap_contract.py.

Skipped (exit 0) when PySide6 or the QtQuick3D.Helpers module is missing, so
CI without the helpers package does not depend on it (the caps simply stay
unpainted there: Cube.qml only loads the mesh through its own Loader, the
same isolation as the arc, see ADR-027).
"""

import math
import sys
import time

from cap_contract import cap_ring, selftest, validate
from qml_check_harness import (
    ROOT,
    boot_qml,
    dispatch,
    qml_problems,
    read_mesh,
    require_pyside,
)

require_pyside("check-cap")


def _wait_for_signals(application, harness):
    # Qt.callLater + the asynchronous Image need a few loop passes before the
    # image-fallback signal has definitely fired (bounded: 2 s worst case).
    application.processEvents()
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        application.processEvents()
        if int(harness.property("unavailableReports")) >= 1:
            break
        time.sleep(0.01)


def _check_harness_inputs(harness):
    # The inputs themselves must come from the ONE geometry source of the
    # solid: faceDistance = W/2/tan(pi/N) + g (polygon apothem) and
    # R = N(W+g)/2pi (cylinderRadius) — computed here independently so a
    # silent formula change in the harness cannot pass both sides quietly.
    sides = int(harness.property("sides"))
    inscribed_sides = int(harness.property("inscribedSides"))
    face_width = float(harness.property("faceWidth"))
    displacement = float(harness.property("displacement"))
    half_height = float(harness.property("halfHeight"))
    apothem = float(harness.property("apothem"))
    radius = float(harness.property("radius"))
    problems = []
    want_apothem = face_width / 2 / math.tan(math.pi / sides) + displacement
    if abs(apothem - want_apothem) > 1e-6:
        problems.append(f"harness apothem {apothem} != faceDistance {want_apothem}")
    want_radius = sides * (face_width + displacement) / (2 * math.pi)
    if abs(radius - want_radius) > 1e-6:
        problems.append(f"harness radius {radius} != cylinderRadius {want_radius}")
    if half_height <= 0:
        problems.append(f"harness halfHeight {half_height} is not positive")
    return (
        sides,
        inscribed_sides,
        int(harness.property("segments")),
        face_width,
        displacement,
        apothem,
        radius,
        problems,
    )


def _check_meshes(
    harness, sides, inscribed_sides, segments, apothem, face_width, radius
):
    """Validate the three real CapMesh instances against the cap contract.

    The two polygon instances must exercise BOTH regimes (the harness picks
    its side counts around the shared apothem so one lands under and one
    above the no-displacement value): if a silent parameter change ever
    collapses them onto one regime, the other branch would leave the gate
    untested — so that is an error, not a narrowing."""
    polygon_mesh = harness.property("polygonMesh")
    inscribed_mesh = harness.property("inscribedMesh")
    disc_mesh = harness.property("discMesh")
    if polygon_mesh is None or inscribed_mesh is None or disc_mesh is None:
        return ["CapMesh not instantiated (polygon, inscribed or disc missing)"]
    polygon_ring = cap_ring(apothem, sides, face_width)
    inscribed_ring = cap_ring(apothem, inscribed_sides, face_width)
    regimes = {polygon_ring[2], inscribed_ring[2]}
    if regimes != {"corners", "inscribed"}:
        return [f"harness polygon meshes cover {sorted(regimes)}, not both regimes"]
    cases = [
        (
            f"polygon cap (N={sides}, {polygon_ring[2]})",
            validate(
                *read_mesh(polygon_mesh, harness.property("polygonIndexes")),
                polygon_ring[1],
                len(polygon_ring[0]),
                apothem,
                sides,
                face_width,
            ),
        ),
        (
            f"polygon cap (N={inscribed_sides}, {inscribed_ring[2]})",
            validate(
                *read_mesh(inscribed_mesh, harness.property("inscribedIndexes")),
                inscribed_ring[1],
                len(inscribed_ring[0]),
                apothem,
                inscribed_sides,
                face_width,
            ),
        ),
        (
            "disc cap (drum, CYLINDER_SEGMENTS)",
            validate(
                *read_mesh(disc_mesh, harness.property("discIndexes")),
                radius,
                segments,
            ),
        ),
    ]
    return [f"{label}: {problem}" for label, found in cases for problem in found]


def _check_degenerate(harness):
    # Degenerate inputs answer EMPTY arrays (the mid-sync contract): no NaN
    # plane can ever reach the scene. A polygon without a face width is
    # degenerate too (the corners have nothing to seal — ADR-027 amendment).
    problems = []
    if int(harness.property("brokenVertexCount")) != 0:
        problems.append("degenerate polygon did NOT answer an empty mesh")
    if int(harness.property("brokenDiscVertexCount")) != 0:
        problems.append("degenerate disc did NOT answer an empty mesh")
    if int(harness.property("zeroWidthVertexCount")) != 0:
        problems.append("zero faceWidth did NOT answer an empty mesh")
    return problems


def _check_cube_pattern(harness):
    # The Cube pattern: ONE mesh for both caps, referenced by two Models.
    problems = []
    if not bool(harness.property("modelsShareMesh")):
        problems.append("the two cap Models do not share the same geometry")
    if not bool(harness.property("modelsHaveSourceCleared")):
        problems.append("Model.source was not accepted empty with a custom geometry")
    if not bool(harness.property("meshesUseTriangles")):
        problems.append("primitiveMode is not ProceduralMesh.Triangles on some mesh")
    return problems


def _check_cap_instances(harness):
    # The real Cap instances (ADR-027): both Models reference the ONE mesh and
    # sit on distinct Y sort centroids (+H/2 / -H/2, the ADR-026 ordering rule
    # extended to the caps); the Image cap with an empty source reports its
    # fallback exactly once and the Gradient cap never reports.
    problems = []
    if not bool(harness.property("capsShareGeometry")):
        problems.append("the Cap instances do not share the single ProceduralMesh")
    if not bool(harness.property("capsHaveOwnCentroids")):
        problems.append("the Cap instances are not at +/- halfHeight centroids")
    reports = int(harness.property("unavailableReports"))
    if reports != 1:
        problems.append(f"image fallback reported {reports} times, expected exactly 1")
    return problems


def _verdict(problems):
    if problems:
        print("check-cap: FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1
    print(
        "check-cap: OK (real ProceduralMesh: ring inside the face planes and the "
        "face corners — inscribed N-gon at g <= 0, 2N corners + inside gap chords "
        "at g > 0, disc radius = cylinderRadius, plane y=0, +Y normals, centred "
        "UVs, CCW winding, one shared mesh, empty on degenerate input)"
    )
    return 0


def main():
    application, _engine, _component, harness, status = boot_qml(
        "check-cap", ROOT / "scripts/check-cap.qml"
    )
    if status is not None:
        return status
    _wait_for_signals(application, harness)

    (
        sides,
        inscribed_sides,
        segments,
        face_width,
        displacement,
        apothem,
        radius,
        problems,
    ) = _check_harness_inputs(harness)
    problems.extend(
        _check_meshes(
            harness, sides, inscribed_sides, segments, apothem, face_width, radius
        )
    )
    problems.extend(_check_degenerate(harness))
    problems.extend(_check_cube_pattern(harness))
    problems.extend(_check_cap_instances(harness))
    problems.extend(qml_problems())

    print(
        f"caps: N={sides} N5={inscribed_sides} W={face_width} g={displacement} "
        f"a={apothem:.1f} R={radius:.1f} seg={segments}"
    )
    return _verdict(problems)


if __name__ == "__main__":
    sys.exit(dispatch(sys.argv, selftest, main))
