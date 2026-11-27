#!/usr/bin/env python3
"""Geometry check of the REAL cap mesh (tapas, ADR-027).

check-constants.py only exercises the pure helpers; this script instantiates
CapMesh.qml itself — the same ProceduralMesh (QtQuick3D.Helpers) that Cube.qml
loads at runtime for both caps — in an offscreen QML engine (no window, no
GPU, no KWin: only the vertex data is read back, never rendered) and
validates what the renderer would consume:

  * polygon cap: the inscribed regular N-gon (N = geometryCount) whose
    APOTHEM equals the live faceDistance — measured per edge: the midpoint of
    every ring edge sits exactly at distance a from the origin and on the
    azimuth grid the faces use, so the cap cannot poke out of the walls. The
    circumradius is derived (a / cos(pi/N)), never a second source;
  * disc cap: radius == R = N(W+g)/2pi (the drum's own formula, three-slot
    drum included), fan-triangulated in CYLINDER_SEGMENTS segments;
  * both: every vertex finite and in the plane y = 0 (the node carries the
    +/- halfHeight, so ONE flat mesh serves both caps), the first vertex is
    the centre, normals exactly +Y and unit-length (the bottom cap flips them
    through its node rotation, never through a second geometry), centred UVs
    in [0, 1] matching u = 0.5 + x/(2 rMax) / v = 0.5 + z/(2 rMax), indexes
    inside [0, vertices), n fan triangles each with a consistent CCW winding
    seen from +Y (every cross product along +Y);
  * the Cube sharing pattern: the top and bottom Models reference the SAME
    geometry (ADR-027: the bottom comes from a node rotation, not a second
    mesh) with an empty source accepted next to a custom geometry;
  * degenerate inputs (mid-sync faceSize, sides < 3, displacement past the
    apothem) answer EMPTY arrays — no NaN plane can ever reach the scene.

--selftest validates the validator against the classic breakages: a NaN
vertex, a flipped triangle, an out-of-range uv, an out-of-range index, a
missing triangle, a ring rotated half a step off the face azimuth grid (the
cap is no longer inscribed), a squeezed-but-in-range uv (centred-linear only
catches that one) and a ring vertex slid +step/4 along the radius so an edge
midpoint falls short of the apothem (the distance branch catches it first).
Each must be REJECTED and the healthy polygon and disc meshes must pass —
otherwise a green run here would prove nothing. Because ANY such slide also
displaces the midpoint azimuth far past its 1e-9 tolerance (measured:
delta/2, while the distance branch needs |mid - apothem| past a 1.7e-3 eps),
the two _edge_problems branches are additionally isolated by direct
synthetic chords: killing either gate must fail the selftest even though
the other branch would still report the mesh. (The
primitiveMode check lives on the harness side: PySide cannot read the enum
value, so the QML compares it where it is a plain number.)

Skipped (exit 0) when PySide6 or the QtQuick3D.Helpers module is missing, so
CI without the helpers package does not depend on it (the caps simply stay
unpainted there: Cube.qml only loads the mesh through its own Loader, the
same isolation as the arc, see ADR-027).
"""

import math
import sys
import time

from qml_check_harness import (
    ROOT,
    boot_qml,
    dispatch,
    mesh_size_problems,
    qml_problems,
    read_mesh,
    require_pyside,
    selftest_verdict,
)

require_pyside("check-cap")


def _finite(*values):
    return all(math.isfinite(v) for v in values)


def _vertex_problems(index, position, r_max, eps):
    """One vertex: finite, on the plane y = 0, centre or exactly on the ring."""
    x, y, z = position
    if not _finite(x, y, z):
        return [f"vertex {index} is not finite: {x}, {y}, {z}"]
    problems = []
    if abs(y) > eps:
        problems.append(f"vertex {index} off the plane: y={y} != 0")
    distance = math.hypot(x, z)
    if index == 0:
        if distance > eps:
            problems.append(f"vertex 0 is not the centre: |x,z|={distance}")
    elif abs(distance - r_max) > eps:
        problems.append(
            f"vertex {index} off the ring: |x,z|={distance:.6f} != {r_max:.6f}"
        )
    return problems


def _check_vertices(positions, r_max, eps):
    # Flat plane at the node origin: y = 0 everywhere (the +/- halfHeight is
    # the NODE position, so one mesh serves both caps — ADR-027).
    problems = []
    for index, position in enumerate(positions):
        problems.extend(_vertex_problems(index, position, r_max, eps))
    return problems


def _normal_problems(index, normal):
    nx, ny, nz = normal
    if not _finite(nx, ny, nz):
        return [f"normal {index} is not finite"]
    if abs(nx) > 1e-9 or abs(nz) > 1e-9 or abs(ny - 1.0) > 1e-9:
        return [f"normal {index} is not +Y: ({nx}, {ny}, {nz})"]
    return []


def _check_normals(normals):
    # Normals: exactly +Y, unit (the bottom cap flips them via the node).
    problems = []
    for index, normal in enumerate(normals):
        problems.extend(_normal_problems(index, normal))
    return problems


def _uv_problems(index, position, uv, r_max):
    x, _, z = position
    u, v = uv
    if not _finite(u, v) or not 0.0 <= u <= 1.0 or not 0.0 <= v <= 1.0:
        return [f"uv {index} out of range: {u}, {v}"]
    want_u = 0.5 + x / (2 * r_max)
    want_v = 0.5 + z / (2 * r_max)
    # The mesh stores float32 (QVector2D/QVector3D): a double-precision
    # 1e-9 expectation would flag the rounding of the read-back values
    # themselves (measured: ~2e-8 at u=0.85). 1e-6 is the float32 noise
    # floor; a mirrored or squeezed uv is O(0.1) away and still fails.
    if abs(u - want_u) > 1e-6 or abs(v - want_v) > 1e-6:
        return [f"uv {index} not centred-linear: ({u}, {v}) != ({want_u}, {want_v})"]
    return []


def _check_uvs(positions, uvs, r_max):
    # UVs: centred on the outer radius, always inside [0, 1].
    problems = []
    for index, position in enumerate(positions):
        problems.extend(_uv_problems(index, position, uvs[index], r_max))
    return problems


def _triangle_problems(triangle, i0, i1, i2, positions):
    if not all(0 <= i < len(positions) for i in (i0, i1, i2)):
        return [f"triangle {triangle} indexes out of range: {i0}, {i1}, {i2}"]
    problems = []
    if i0 != 0:
        problems.append(f"triangle {triangle} does not start at the centre: {i0}")
    v0 = positions[i0]
    v1 = positions[i1]
    v2 = positions[i2]
    e1 = [v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]]
    e2 = [v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]]
    cross_y = e1[2] * e2[0] - e1[0] * e2[2]
    if cross_y <= 0.0:
        problems.append(f"triangle {triangle} wound away from +Y (flipped?)")
    return problems


def _check_fan(indexes, positions):
    # Indexes + fan structure + winding (CCW seen from +Y: every cross
    # product along +Y, the same outward convention as the arc mesh).
    problems = []
    for triangle in range(len(indexes) // 3):
        i0, i1, i2 = indexes[triangle * 3 : triangle * 3 + 3]
        problems.extend(_triangle_problems(triangle, i0, i1, i2, positions))
    return problems


def _edge_problems(k, a_pt, b_pt, apothem, step, eps):
    """One ring edge: its midpoint on the apothem and on the azimuth grid."""
    mid_x = (a_pt[0] + b_pt[0]) / 2.0
    mid_z = (a_pt[2] + b_pt[2]) / 2.0
    mid = math.hypot(mid_x, mid_z)
    problems = []
    if abs(mid - apothem) > eps:
        problems.append(f"edge {k} midpoint |x,z|={mid:.6f} != apothem {apothem:.6f}")
    angle = math.atan2(mid_x, mid_z) % step
    if min(angle, step - angle) > 1e-9:
        problems.append(
            f"edge {k} midpoint off the face azimuth grid ({angle} mod {step})"
        )
    return problems


def _check_inscribed(positions, apothem, sides, eps, vertex_count):
    # Polygon-only contract (ADR-027): the cap is INSCRIBED — the midpoint of
    # every edge sits on faceDistance and on the face azimuth grid, so each
    # side lies on the plane of a face and nothing protrudes.
    if apothem is None or sides is None or len(positions) != vertex_count:
        return []
    step = 2 * math.pi / sides
    problems = []
    for k in range(sides):
        a_pt = positions[1 + k]
        b_pt = positions[1 + (k + 1) % sides]
        problems.extend(_edge_problems(k, a_pt, b_pt, apothem, step, eps))
    return problems


def validate(
    positions, normals, uvs, indexes, r_max, half_count, apothem=None, sides=None
):
    """Validate one flat cap mesh (polygon when apothem is given, else disc).

    r_max: the outer radius everything scales against (circumradius of the
    polygon, radius of the disc). half_count: number of ring vertices (sides
    or segments). Returns human-readable problems (empty = valid).

    The blocks are private helpers (_check_*) so each one stays simple; the
    order of the extends below IS the order of the original checks — every
    problem message is produced by exactly one helper, never re-worded."""
    vertex_count = half_count + 1
    expected_indexes = half_count * 3
    eps = 1e-6 * max(1.0, r_max)

    problems, malformed = mesh_size_problems(
        positions, normals, uvs, indexes, vertex_count, expected_indexes
    )
    if malformed:
        return problems

    problems.extend(_check_vertices(positions, r_max, eps))
    problems.extend(_check_normals(normals))
    problems.extend(_check_uvs(positions, uvs, r_max))
    problems.extend(_check_fan(indexes, positions))
    if len(indexes) % 3 != 0:
        problems.append(f"indexes count {len(indexes)} is not a multiple of 3")
    problems.extend(_check_inscribed(positions, apothem, sides, eps, vertex_count))
    return problems


def reference_polygon(apothem, sides):
    """Python twin of capPolygonGeometry() — the selftest's good mesh."""
    r_circ = apothem / math.cos(math.pi / sides)
    step = 2 * math.pi / sides
    positions = [(0.0, 0.0, 0.0)]
    normals = [(0.0, 1.0, 0.0)]
    uvs = [(0.5, 0.5)]
    for k in range(sides):
        alpha = step * (k + 0.5)
        x = r_circ * math.sin(alpha)
        z = r_circ * math.cos(alpha)
        positions.append((x, 0.0, z))
        normals.append((0.0, 1.0, 0.0))
        uvs.append((0.5 + x / (2 * r_circ), 0.5 + z / (2 * r_circ)))
    indexes = []
    for k in range(sides):
        indexes += [0, 1 + k, 1 + (k + 1) % sides]
    return positions, normals, uvs, indexes, r_circ


def reference_disc(radius, segments):
    """Python twin of capDiscGeometry()."""
    step = 2 * math.pi / segments
    positions = [(0.0, 0.0, 0.0)]
    normals = [(0.0, 1.0, 0.0)]
    uvs = [(0.5, 0.5)]
    for k in range(segments):
        x = radius * math.sin(step * k)
        z = radius * math.cos(step * k)
        positions.append((x, 0.0, z))
        normals.append((0.0, 1.0, 0.0))
        uvs.append((0.5 + x / (2 * radius), 0.5 + z / (2 * radius)))
    indexes = []
    for k in range(segments):
        indexes += [0, 1 + k, 1 + (k + 1) % segments]
    return positions, normals, uvs, indexes, radius


def _good_mesh_problems(apothem, sides, radius, segments):
    """Both healthy reference meshes must pass the validator."""
    failures = []
    positions, normals, uvs, indexes, r_circ = reference_polygon(apothem, sides)
    problems = validate(positions, normals, uvs, indexes, r_circ, sides, apothem, sides)
    if problems:
        failures.append(f"the reference polygon did not pass: {problems[0]}")
    positions, normals, uvs, indexes, r_disc = reference_disc(radius, segments)
    problems = validate(positions, normals, uvs, indexes, r_disc, segments)
    if problems:
        failures.append(f"the reference disc did not pass: {problems[0]}")
    return failures


def _mutate_nan_vertex(m):
    m[0][3] = (float("nan"), 0.0, 0.0)


def _mutate_flip(m):
    t = 3 * (len(m[3]) // 3 - 1)  # last triangle: swap its two ring indexes
    m[3][t + 1], m[3][t + 2] = m[3][t + 2], m[3][t + 1]


def _mutate_bad_uv(m):
    m[2][2] = (1.5, 0.25)


def _mutate_bad_index(m):
    m[3][2] = 99999


def _mutate_missing_triangle(m):
    del m[3][-3:]


def _mutate_half_step(m):
    # Rigid half-step rotation of the ring: azimuth step*(k+0.5) -> step*k,
    # so the vertices land where the edge midpoints used to be. The ring
    # radius is untouched (measured drift: 0.0, the vertices/radius gate
    # stays quiet) and the uvs rotate WITH their vertices (u = 0.5 + x/2r
    # recomputed), so the plane, normal and uv gates stay quiet too. What
    # remains is the inscription contract itself (ADR-027): every edge
    # midpoint leaves the face azimuth grid (measured offset: step/2 =
    # 0.628 rad against a 1e-9 tolerance). |mid - apothem| stays exactly a
    # (a rotation is rigid), so the distance branch is not the one that
    # fires — the azimuth-grid branch is.
    r = m[4]
    step = 2 * math.pi / (len(m[0]) - 1)
    cos, sin = math.cos(step / 2), math.sin(step / 2)
    positions = [m[0][0]]
    uvs = [m[2][0]]
    for x, y, z in m[0][1:]:
        rx = x * cos - z * sin
        rz = z * cos + x * sin
        positions.append((rx, y, rz))
        uvs.append((0.5 + rx / (2 * r), 0.5 + rz / (2 * r)))
    m[0] = positions
    m[2] = uvs


def _mutate_off_radius_midpoint(m):
    # Slide ONLY the first ring vertex +step/4 along the ring (measured with
    # n=5, a=1380: edge 0 midpoint |x,z|=1206.164227 against apothem 1380,
    # a 173-unit drop against an eps of 1.7e-3; edge 1 midpoint 1519.86).
    # The vertex stays exactly on the ring radius (the vertices/radius gate
    # is quiet), the plane, the normals and the fan are untouched (cross
    # products stay along +Y: every ring gap is 0.75..1.25 of step, far
    # below the flip threshold) and the uv follows the vertex (u = 0.5 +
    # x/2r recomputed), so the FIRST problem is the edge midpoint distance —
    # the apothem branch of _edge_problems — exactly the "a side no longer
    # lying on a face plane" breakage of ADR-027. The azimuth grid fires on
    # the SAME edges as a side effect of any ring slide (measured: a slide
    # large enough to move |mid| past eps of 1.7e-3 displaces the midpoint
    # azimuth by delta/2 > 1.7e-6 rad, five orders above the 1e-9 grid
    # tolerance — no mesh-level delta isolates the distance branch, hence
    # the direct branch probe _edge_branch_problems below).
    r = m[4]
    step = 2 * math.pi / (len(m[0]) - 1)
    x, y, z = m[0][2]
    alpha = math.atan2(x, z) + step / 4
    x2 = r * math.sin(alpha)
    z2 = r * math.cos(alpha)
    m[0][2] = (x2, y, z2)
    m[2][2] = (0.5 + x2 / (2 * r), 0.5 + z2 / (2 * r))


def _mutate_uv_squeezed(m):
    # Squeeze the u of a ring vertex (index 1 of the ring, never the centre)
    # towards the middle: the value stays inside [0, 1] so the range branch
    # cannot fire — only the centred-linear branch can catch it (measured:
    # du = 4.8e-2 polygon / 4.9e-3 disc against a 1e-6 tolerance).
    u, v = m[2][2]
    m[2][2] = (0.5 + 0.9 * (u - 0.5), v)


# The classic breakages: one mutation per entry, labels verbatim in the log.
# Each entry is (label, mutate, shapes). "cap not inscribed" and "cap edge
# off the apothem" are polygon-only: the disc contract fixes radius, fan and
# centred uvs but NEVER the azimuth (measured: a half-step-rotated disc and
# a one-vertex-slid disc both validate clean — another rotation/slide of a
# rotationally symmetric drum is still a valid drum), so a disc run of
# either mutation would prove nothing. With this table the selftest reports
# 14 detections: 6 mesh breakages x 2 shapes + 2 polygon-only breakages +
# the healthy-mesh checks print no PASS line.
MUTATIONS = [
    ("NaN vertex", _mutate_nan_vertex, ("polygon", "disc")),
    ("inverted winding", _mutate_flip, ("polygon", "disc")),
    ("uv out of range", _mutate_bad_uv, ("polygon", "disc")),
    ("index out of range", _mutate_bad_index, ("polygon", "disc")),
    ("missing triangle", _mutate_missing_triangle, ("polygon", "disc")),
    ("cap not inscribed", _mutate_half_step, ("polygon",)),
    ("uv not centred", _mutate_uv_squeezed, ("polygon", "disc")),
    ("cap edge off the apothem", _mutate_off_radius_midpoint, ("polygon",)),
]


def _broken_mesh_problems(kind, mutate, apothem, sides, radius, segments):
    """Apply one mutation to a fresh reference mesh and re-validate it."""
    if kind == "polygon":
        good = reference_polygon(apothem, sides)
    else:
        good = reference_disc(radius, segments)
    broken = [list(good[0]), list(good[1]), list(good[2]), list(good[3]), good[4]]
    mutate(broken)
    if kind == "polygon":
        return validate(
            broken[0],
            broken[1],
            broken[2],
            broken[3],
            broken[4],
            sides,
            apothem,
            sides,
        )
    return validate(broken[0], broken[1], broken[2], broken[3], broken[4], segments)


def _edge_branch_problems():
    """Isolate the two _edge_problems branches with direct synthetic chords.

    A full ring slide can never exercise ONLY the apothem-distance branch:
    any delta moving |mid| past eps (measured threshold: 3.4e-6 rad) also
    displaces the midpoint azimuth by delta/2, five orders of magnitude
    above the 1e-9 grid tolerance — so with the distance gate disabled the
    mesh-level cases would still be caught by the grid branch and a green
    selftest would not prove the distance gate runs. These two chords do:
    midpoint ON the apothem but off the grid must raise only the grid
    problem, midpoint ON the grid (azimuth 0) but short of the apothem must
    raise only the distance problem. If either branch is killed, exactly
    one assertion fails and the selftest exits non-zero."""
    sides, apothem = 5, 1380.0
    r_circ = apothem / math.cos(math.pi / sides)
    step = 2 * math.pi / sides
    eps = 1e-6 * max(1.0, r_circ)
    failures = []
    # Chord through the origin: midpoint (0, 0) is a whole apothem short,
    # atan2(0, 0) = 0 keeps the azimuth grid quiet.
    chord = _edge_problems(
        0, (r_circ, 0.0, 0.0), (-r_circ, 0.0, 0.0), apothem, step, eps
    )
    if len(chord) != 1 or "apothem" not in chord[0]:
        failures.append(f"distance branch not isolated: {chord}")
    # Chord centred on the grid azimuth step/2 at distance exactly apothem
    # (endpoints are the midpoint +/- a unit chord, so averaging returns the
    # midpoint): the distance stays quiet, the grid must fire.
    theta = step / 2
    mx, mz = apothem * math.sin(theta), apothem * math.cos(theta)
    px, pz = math.cos(theta), -math.sin(theta)
    chord = _edge_problems(
        0,
        (mx + px, 0.0, mz + pz),
        (mx - px, 0.0, mz - pz),
        apothem,
        step,
        eps,
    )
    if len(chord) != 1 or "azimuth" not in chord[0]:
        failures.append(f"azimuth-grid branch not isolated: {chord}")
    return failures


def selftest():
    """The validator must pass both good meshes and reject every breakage.

    Coverage = the two healthy meshes + 8 mesh-level mutations (14 PASS
    detections: 6 x both shapes, 2 polygon-only) + the two direct branch
    probes that keep _edge_problems' distance and grid gates independently
    killable."""
    apothem, sides = 1380.0, 5
    radius, segments = 1693.4, 64
    failures = _good_mesh_problems(apothem, sides, radius, segments)
    failures.extend(_edge_branch_problems())

    for kind in ("polygon", "disc"):
        for name, mutate, shapes in MUTATIONS:
            if kind not in shapes:
                continue
            label = f"{kind}: {name}"
            found = _broken_mesh_problems(
                kind, mutate, apothem, sides, radius, segments
            )
            if not found:
                failures.append(f"{label} was NOT detected")
            else:
                print(f"  PASS detects {label}: {found[0]}")

    return selftest_verdict("check-cap", failures)


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
        int(harness.property("segments")),
        face_width,
        displacement,
        apothem,
        radius,
        problems,
    )


def _check_meshes(harness, sides, segments, apothem, radius):
    """Validate the two real CapMesh instances against the cap contract."""
    polygon_mesh = harness.property("polygonMesh")
    disc_mesh = harness.property("discMesh")
    if polygon_mesh is None or disc_mesh is None:
        return ["CapMesh not instantiated (polygon or disc missing)"]
    r_circ = apothem / math.cos(math.pi / sides)
    cases = [
        (
            "polygon cap (inscribed N-gon)",
            validate(
                *read_mesh(polygon_mesh, harness.property("polygonIndexes")),
                r_circ,
                sides,
                apothem,
                sides,
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
    # plane can ever reach the scene.
    problems = []
    if int(harness.property("brokenVertexCount")) != 0:
        problems.append("degenerate polygon did NOT answer an empty mesh")
    if int(harness.property("brokenDiscVertexCount")) != 0:
        problems.append("degenerate disc did NOT answer an empty mesh")
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
        "check-cap: OK (real ProceduralMesh: inscribed apothem = faceDistance, "
        "disc radius = cylinderRadius, plane y=0, +Y normals, centred UVs, "
        "CCW winding, one shared mesh, empty on degenerate input)"
    )
    return 0


def main():
    application, _engine, _component, harness, status = boot_qml(
        "check-cap", ROOT / "scripts/check-cap.qml"
    )
    if status is not None:
        return status
    _wait_for_signals(application, harness)

    sides, segments, face_width, displacement, apothem, radius, problems = (
        _check_harness_inputs(harness)
    )
    problems.extend(_check_meshes(harness, sides, segments, apothem, radius))
    problems.extend(_check_degenerate(harness))
    problems.extend(_check_cube_pattern(harness))
    problems.extend(_check_cap_instances(harness))
    problems.extend(qml_problems())

    print(
        f"caps: N={sides} W={face_width} g={displacement} a={apothem:.1f} "
        f"R={radius:.1f} seg={segments}"
    )
    return _verdict(problems)


if __name__ == "__main__":
    sys.exit(dispatch(sys.argv, selftest, main))
