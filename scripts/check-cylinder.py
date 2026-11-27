#!/usr/bin/env python3
"""Geometry check of the REAL cylinder arc mesh (Shape == Cylinder, ADR-025).

check-constants.py only exercises the pure helpers; this script instantiates
CylinderArcMesh.qml itself — the same ProceduralMesh (QtQuick3D.Helpers) that
Cube.qml loads at runtime — in an offscreen QML engine (no window, no GPU,
no KWin: only the vertex data is read back, never rendered) and validates
what the renderer would consume:

  * every vertex finite, and on the node-centred cylinder (ADR-026): the arc
    wraps the axis (0, 0, -R) of the mesh's OWN frame, so sqrt(x^2 + (z+R)^2)
    == R for all arc-lengths s, both height rows at y = -H/2 and +H/2 — the
    arc's mid-point sits at the node origin and every face gets its radius
    from the Model's position (polygon placement), which is what gives each
    face a distinct sort centroid for the transparent pass;
  * uvs in [0, 1] with u LINEAR in s (u = s/W: the isometry of ADR-002 — a
    non-linear u would stretch the wallpaper across the arc);
  * total arc length, integrated from the vertex angles (sum of R * dphi),
    equal to W: the arc measures the face and the texture is never squeezed;
  * the wedge between two neighbouring arcs measures exactly the effective
    gap g (R * (2*pi/N - W/R) = g), and a NEGATIVE displacement clamps to
    g = 0: the open-arc radius must shrink back to the closed-cylinder one
    and the whole mesh must come out identical;
  * normals unit-length and radial (outward), indexes inside [0, vertices),
    and a consistent CCW winding seen from outside (every triangle's cross
    product points along the radial normal — the #Rectangle convention).

--selftest validates the validator against NINE breakages: a flipped
triangle, an off-cylinder vertex, an out-of-range uv, an out-of-range
index, a NaN vertex, a missing triangle, an inverted u (isometry broken
while every point stays on R), an arc whose angle is wrong at fixed |P|
(only the integrated arc-length can see it) and mirrored v rows (the
#Rectangle parity is a documented contract). Each must be REJECTED and a
healthy mesh must pass — otherwise a green run here would prove nothing.
(The primitiveMode check lives on the harness side: PySide cannot read
the enum value, so the QML compares it where it is a plain number.)

Skipped (exit 0) when PySide6 or the QtQuick3D.Helpers module is missing, so
CI without the helpers package does not depend on it (the effect degrades to
the polygon look there anyway: Cube.qml only loads the mesh in cylinder
mode, see ADR-025).
"""

import math
import sys

from qml_check_harness import (
    ROOT,
    boot_qml,
    dispatch,
    mesh_size_problems,
    qml_problems,
    read_mesh,
    require_pyside,
    selftest_verdict,
    to_xyz,
)

require_pyside("check-cylinder")


def validate(
    positions, normals, uvs, indexes, width, height, radius, segments, primitive=5
):
    """Return a list of human-readable problems (empty = valid mesh)."""
    problems = []
    vertex_count = (segments + 1) * 2
    expected_indexes = segments * 6

    def finite(value):
        return math.isfinite(value)

    problems, malformed = mesh_size_problems(
        positions, normals, uvs, indexes, vertex_count, expected_indexes
    )
    if malformed:
        return problems

    radial_eps = 1e-6 * max(1.0, radius)
    for index, (x, y, z) in enumerate(positions):
        if not (finite(x) and finite(y) and finite(z)):
            problems.append(f"vertex {index} is not finite: {x}, {y}, {z}")
            continue
        # Cylindricity (ADR-026): every vertex sits on the circle of radius
        # R around the node-local axis (0, 0, -R), for BOTH height rows.
        drift = abs(math.hypot(x, z + radius) - radius)
        if drift > radial_eps:
            problems.append(
                f"vertex {index} off the cylinder: |x,(z+R)|={math.hypot(x, z + radius):.6f} != R={radius:.6f}"
            )
        # Two rows at the exact half-height (column i: bottom 2i, top 2i+1).
        expect_y = -height / 2 if index % 2 == 0 else height / 2
        if abs(y - expect_y) > radial_eps:
            problems.append(f"vertex {index} y={y} != {expect_y} (row of the arc)")

    for index, (u, v) in enumerate(uvs):
        if not (finite(u) and finite(v)) or not 0.0 <= u <= 1.0 or not 0.0 <= v <= 1.0:
            problems.append(f"uv {index} out of range: {u}, {v}")
            continue
        # Isometry: u must be LINEAR in s (u = i/segments across the column).
        column = index // 2
        if abs(u - column / segments) > 1e-9:
            problems.append(f"uv {index} not linear in s: u={u} != {column / segments}")
        expect_v = 0.0 if index % 2 == 0 else 1.0  # #Rectangle convention: v=0 bottom
        if abs(v - expect_v) > 1e-9:
            problems.append(f"uv {index} v={v} != {expect_v} (row)")

    # Integrated arc length from the vertex angles AROUND THE NODE-LOCAL
    # AXIS (0, 0, -R): sum R*dphi over the bottom row must equal W exactly
    # (theta = W/R is the whole point).
    length = 0.0
    for column in range(1, segments + 1):
        x0, _, z0 = positions[2 * (column - 1)]
        x1, _, z1 = positions[2 * column]
        u0 = z0 + radius
        u1 = z1 + radius
        length += radius * math.atan2(x1 * u0 - x0 * u1, x0 * x1 + u0 * u1)
    if abs(length - width) > 1e-6 * max(1.0, width):
        problems.append(f"arc length {length:.6f} != face width {width:.6f}")

    # Normals: unit and radial outward (x, 0, z)/R on the axis.
    for index, (nx, ny, nz) in enumerate(normals):
        if not (finite(nx) and finite(ny) and finite(nz)):
            problems.append(f"normal {index} is not finite")
            continue
        px, _, pz = positions[index]
        dot = nx * nx + ny * ny + nz * nz
        if abs(dot - 1.0) > 1e-6:
            problems.append(f"normal {index} not unit: {math.sqrt(dot)}")
        radial = (px * nx + (pz + radius) * nz) / max(radius, 1e-12)
        if radial < 1.0 - 1e-6:
            problems.append(
                f"normal {index} not radial outward: dot with (x,0,z) = {radial}"
            )
        if abs(ny) > 1e-9:
            problems.append(
                f"normal {index} has y={ny} (a vertical arc has flat normals)"
            )

    # Indexes + winding.
    if expected_indexes == 0:
        return problems
    for triangle in range(len(indexes) // 3):
        i0, i1, i2 = indexes[triangle * 3 : triangle * 3 + 3]
        if not all(0 <= i < len(positions) for i in (i0, i1, i2)):
            problems.append(
                f"triangle {triangle} indexes out of range: {i0}, {i1}, {i2}"
            )
            continue
        v0 = positions[i0]
        v1 = positions[i1]
        v2 = positions[i2]
        e1 = [v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]]
        e2 = [v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]]
        cross = [
            e1[1] * e2[2] - e1[2] * e2[1],
            e1[2] * e2[0] - e1[0] * e2[2],
            e1[0] * e2[1] - e1[1] * e2[0],
        ]
        # Outward test: the cross product must lean onto the radial
        # direction of the triangle centroid measured from the node-local
        # axis (CCW seen from OUTSIDE).
        mid_x = (v0[0] + v1[0] + v2[0]) / 3.0
        mid_z = (v0[2] + v1[2] + v2[2]) / 3.0 + radius
        if cross[0] * mid_x + cross[2] * mid_z <= 0.0:
            problems.append(f"triangle {triangle} wound inwards (flipped?)")
    if len(indexes) % 3 != 0:
        problems.append(f"indexes count {len(indexes)} is not a multiple of 3")
    return problems


def reference_mesh(width=2560.0, height=1440.0, radius=1000.0, segments=64):
    """Python twin of cylinderArcGeometry() — the selftest's good mesh."""
    positions = []
    normals = []
    uvs = []
    indexes = []
    for column in range(segments + 1):
        phi = (width * column / segments - width / 2) / radius
        sine, cosine = math.sin(phi), math.cos(phi)
        positions.append((radius * sine, -height / 2, radius * cosine - radius))
        positions.append((radius * sine, height / 2, radius * cosine - radius))
        normals.append((sine, 0.0, cosine))
        normals.append((sine, 0.0, cosine))
        uvs.append((column / segments, 0.0))
        uvs.append((column / segments, 1.0))
    for column in range(segments):
        a = 2 * column
        b, c, d = a + 1, a + 2, a + 3
        indexes += [a, c, b]
        indexes += [b, c, d]
    return positions, normals, uvs, indexes, 5


def selftest():
    """The validator must pass the good mesh and reject every breakage."""
    width, height, radius, segments = 2560.0, 1440.0, 1693.4, 64
    failures = []

    positions, normals, uvs, indexes, primitive = reference_mesh(
        width, height, radius, segments
    )
    problems = validate(
        positions, normals, uvs, indexes, width, height, radius, segments, primitive
    )
    if problems:
        failures.append(f"the reference mesh did not pass: {problems[0]}")

    def mutation(name, mutate):
        good = reference_mesh(width, height, radius, segments)
        broken = [list(good[0]), list(good[1]), list(good[2]), list(good[3]), good[4]]
        mutate(broken)
        found = validate(
            broken[0],
            broken[1],
            broken[2],
            broken[3],
            width,
            height,
            radius,
            segments,
            broken[4],
        )
        if not found:
            failures.append(f"{name} was NOT detected")
        else:
            print(f"  PASS detects {name}: {found[0]}")

    def flip(m):
        m[3][0], m[3][1] = m[3][1], m[3][0]  # swap two indexes of triangle 0

    def off_radius(m):
        x, y, z = m[0][0]
        # x scaled away from the node-local axis at (0, 0, -R)
        m[0][0] = (x * 1.2, y, z)

    def bad_uv(m):
        _, v = m[2][4]
        m[2][4] = (1.5, v)

    def bad_index(m):
        m[3][2] = 99999

    def nan_vertex(m):
        m[0][7] = (float("nan"), 0.0, 0.0)

    def missing_triangle(m):
        del m[3][-3:]

    def inverted_u(m):
        seg = segments
        m[2] = [(1.0 - (i // 2) / seg, v) for (i, (_, v)) in enumerate(m[2])]

    def wrong_theta(m):
        # |P - (0,0,-R)| stays exactly on R, but the arc spans 1.1x the
        # isometric angle: only the integrated arc-length check (theta = W/R)
        # can catch this.
        stretched = []
        norms = []
        for (x, y, z), _ in zip(m[0], m[1]):
            phi = math.atan2(x, z + radius) * 1.1
            r = math.hypot(x, z + radius)
            stretched.append((r * math.sin(phi), y, r * math.cos(phi) - radius))
            norms.append((math.sin(phi), 0.0, math.cos(phi)))
        m[0] = stretched
        m[1] = norms

    def mirrored_v(m):
        # The #Rectangle v parity (bottom row 0) is a documented contract
        # (ADR-025): an upside-down arc must fail the gate, not the eyes.
        m[2] = [(u, 1.0 - v) for (u, v) in m[2]]

    for name, fn in [
        ("flipped winding", flip),
        ("off-cylinder vertex", off_radius),
        ("uv out of range", bad_uv),
        ("index out of range", bad_index),
        ("NaN vertex", nan_vertex),
        ("missing triangle", missing_triangle),
        ("inverted u (isometry broken)", inverted_u),
        ("arc angle wrong at fixed R", wrong_theta),
        ("mirrored v rows", mirrored_v),
    ]:
        mutation(name, fn)

    return selftest_verdict("check-cylinder", failures)


def main():
    application, _engine, _component, harness, status = boot_qml(
        "check-cylinder", ROOT / "scripts/check-cylinder.qml"
    )
    if status is not None:
        return status
    application.processEvents()

    problems: list[str] = []
    width = float(harness.property("faceWidth"))
    height = float(harness.property("faceHeight"))
    segments = int(harness.property("segments"))
    face_count = int(harness.property("faceCount"))

    cases = [
        (
            "drum closed (g=0)",
            float(harness.property("radiusClosed")),
            harness.property("closedMesh"),
            harness.property("closedIndexes"),
            face_count * width / (2 * math.pi),
        ),
        (
            "drum open (g=100)",
            float(harness.property("radiusOpen")),
            harness.property("openMesh"),
            harness.property("openIndexes"),
            face_count * (width + 100.0) / (2 * math.pi),
        ),
        (
            "negative clamps to 0",
            float(harness.property("radiusNegative")),
            harness.property("negativeMesh"),
            harness.property("negativeIndexes"),
            face_count * width / (2 * math.pi),
        ),
        (
            # The three-slot drum of 1-2 desktops (ADR-025 pt.11, recast by
            # ADR-026): N = 3 with g = 0 gives R = 3W/2pi, W measured as
            # before. The same validator must hold: node-local cylindricity,
            # linear u, arc length = W, winding. (g > 0 is the ordinary drum
            # formula, covered by the open-drum case.)
            "three-slot drum, g=0 (2 faces)",
            float(harness.property("radiusSlots")),
            harness.property("slotsMesh"),
            harness.property("slotsIndexes"),
            3 * width / (2 * math.pi),
        ),
    ]
    for label, radius, mesh, indexes, expected in cases:
        if mesh is None:
            problems.append(f"{label}: CylinderArcMesh not instantiated")
            continue
        if radius <= 0:
            problems.append(f"{label}: radius {radius} is not positive")
            continue
        # R must be exactly the formula's value, straight from constants.js.
        if abs(radius - expected) > 1e-6:
            problems.append(f"{label}: radius {radius} != expected {expected}")
        found = validate(*read_mesh(mesh, indexes), width, height, radius, segments)
        for problem in found:
            problems.append(f"{label}: {problem}")

    # theta = W/R of the three-slot drum arc (g = 0) must be exactly 2pi/3
    # (the generator is shared with the drum: 120 degrees comes from
    # R = 3W/2pi, not from a second code path).
    theta = float(harness.property("slotsTheta"))
    if abs(theta - 2 * math.pi / 3) > 1e-9:
        problems.append(f"segment theta {theta} != 2pi/3 = {2 * math.pi / 3}")

    # The clamp contract, end to end: the negative-gap mesh must be
    # IDENTICAL to the closed one (same R, same vertices).
    closed = cases[0][2]
    negative = cases[2][2]
    if closed is not None and negative is not None:
        cp = [to_xyz(v) for v in closed.property("positions")]
        np_ = [to_xyz(v) for v in negative.property("positions")]
        if cp != np_:
            problems.append(
                "negative displacement did NOT clamp: mesh differs from the closed one"
            )

    if not bool(harness.property("meshesUseTriangles")):
        problems.append("primitiveMode is not ProceduralMesh.Triangles on some mesh")

    if not bool(harness.property("modelsShareMesh")):
        problems.append("two Models cannot reference the same geometry")
    if not bool(harness.property("modelsHaveSourceCleared")):
        problems.append("Model.source was not accepted empty with a custom geometry")

    problems.extend(qml_problems())

    print(f"cylinder: N={face_count} W={width} H={height} seg={segments}")
    if problems:
        print("check-cylinder: FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1
    print(
        "check-cylinder: OK (real ProceduralMesh: node-centred cylindricity, isometric UVs, "
        "arc length = W, gap clamp, radial normals, CCW winding, shared geometry)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(dispatch(sys.argv, selftest, main))
