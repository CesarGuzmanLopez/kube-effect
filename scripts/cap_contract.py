"""The cap-ring contract (ADR-027 + the face-corner amendment).

Pure validator for the polygon/disc cap meshes produced by
package/contents/ui/capGeometry.js, plus the --selftest that keeps the
validator itself honest. scripts/check-cap.py boots the REAL CapMesh.qml
offscreen, reads the ProceduralMesh back and runs validate() on it; the
geometry clauses documented there are implemented here:

  * per-face assertions in the face's LOCAL frame (normal n_k = (sin, cos),
    tangent t_k = (cos, -sin) at azimuth step*k) — never a world-axis bound
    (measured: the correct n=3 d=300 ring has max |x| = 1539.8 > W/2 = 1280):
      - hard prism invariant: dot(v, n_k) <= apothem + eps for every ring
        vertex v and every face k (the cap never peeks out of the walls —
        also the kill for the single min()-clamp draft, measured 694.4 vs
        the apothem 539.0 at n=3 d=-200);
      - corner bound: a vertex on a face plane stays within that face's
        corner, |dot(v, t_k)| <= faceWidth/2 + eps (the shipped
        plane-intersection ring violated exactly this: +173.2 px at n=3
        d=100, +519.6 px at n=3 d=300);
  * regime d <= 0: the ring COLLAPSES to the inscribed N-gon (sides
    vertices at apothem/cos(pi/N), edge midpoints on the apothem and on
    the face azimuth grid — the original ADR-027 contract);
  * regime d > 0: 2N face-corner vertices at hypot(apothem, faceWidth/2),
    each face owning an exact -W/2/+W/2 side on its plane, the leftover
    edges straight gap chords whose midpoints project strictly INSIDE the
    planes (the shell shows through the holes);
  * disc and polygon common clauses (plane y = 0, ring radius, normals,
    centred UVs, fan winding) as the module docstring of check-cap.py
    describes.

--selftest: the three healthy references must pass; the eleven mutations
(the eight classic breakages + the pre-fix N-gon under d > 0, the corner
slid past W/2 and the vertex pulled off its plane) must be rejected; and
the SIX DIRECT branch probes keep every individual clause killable:
_edge_branch_problems (the two midpoint branches), _regime_branch_problems
(the prism invariant and the corner bound), _face_sides_branch_problems
(the face-side exactness, blind until a shrunk-face ring isolates it) and
_gap_chords_branch_problems (the implied gap-chord margin: closed-form
identity plus a lifted chord the helper MUST report). Overriding any of
the guarded helpers with a stub must make the selftest exit non-zero, so
a green run here proves each clause is live code.
"""

import math

from qml_check_harness import mesh_size_problems, selftest_verdict

# Azimuth band where the face-corner and plane-intersection vertices
# coincide — the mirror of CAP_BETA_TOL in capGeometry.js, so Python and the
# runtime pick the same side of d = 0 (float jitter can otherwise put
# betaFace a single ulp under halfStep exactly at d = 0, measured at n = 4).
BETA_TOL = 1e-9
# Azimuth-grid tolerance for ring-edge checks: above the ~1.7e-8 rad float32
# read-back noise of a real mesh, orders below any genuine off-grid chord.
GRID_TOL = 1e-6


def _finite(*values):
  return all(math.isfinite(v) for v in values)


def _face_frame(theta):
  """Local frame (normal, tangent) of the face at azimuth theta, in (x, z).

  dot(v, n_k) is the distance along the face plane's normal (== apothem
  for a vertex lying ON that plane); dot(v, t_k) is the position across
  the face's width. Every cap contract is stated in this per-face frame."""
  return (math.sin(theta), math.cos(theta)), (math.cos(theta), -math.sin(theta))


def _dot2(a, b):
  return a[0] * b[0] + a[1] * b[1]


def cap_ring(apothem, sides, face_width):
  """Python mirror of the generator's branch rule (capGeometry.js):
  returns (ring azimuths, ring radius, regime).

  "inscribed" (d <= 0): sides vertices at rc = apothem/cos(pi/sides);
  "corners" (d > 0): 2*sides vertices at rho = hypot(apothem, faceWidth/2).
  The tolerance band collapses d = 0 onto the inscribed side, exactly
  like the JS."""
  step = 2 * math.pi / sides
  half = math.pi / sides
  beta = math.atan((face_width / 2) / apothem)
  if beta >= half - BETA_TOL:
    return (
      [step * (k + 0.5) for k in range(sides)],
      apothem / math.cos(half),
      "inscribed",
    )
  alphas = []
  for k in range(sides):
    alphas += [step * k - beta, step * k + beta]
  return alphas, math.hypot(apothem, face_width / 2), "corners"


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
    problems.append(f"vertex {index} off the ring: |x,z|={distance:.6f} != {r_max:.6f}")
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
  # GRID_TOL: the midpoint azimuth of a REAL float32 ring carries ~1.7e-8
  # rad of read-back noise (measured at N=5, rc=1705.8 — the historical
  # 1e-9 was only ever exercised on the double-precision references, it
  # is under the float32 floor of the mesh the harness reads back). A
  # mesh truly off the grid is O(step) away, so 1e-6 rad separates both
  # worlds with orders of margin.
  if min(angle, step - angle) > GRID_TOL:
    problems.append(f"edge {k} midpoint off the face azimuth grid ({angle} mod {step})")
  return problems


def _prism_problems(ring, apothem, sides, step, eps):
  """HARD invariant (both regimes): no ring vertex may project past ANY
  face plane, dot(v, n_k) <= apothem + eps. A vertex on its own face's
  plane satisfies it with equality, so healthy meshes stay quiet. This is
  the assertion that was missing: the single min(beta, halfStep) clamp
  draft parked ring vertices at the plane-intersection azimuth with the
  corner radius — out of the walls for d < 0 (measured 694.4 against the
  apothem 539.0 at n=3 d=-200) — and any outward radial slip pokes here
  too."""
  problems = []
  for index, (x, _, z) in enumerate(ring, start=1):
    v = (x, z)
    for k in range(sides):
      n_k, _ = _face_frame(step * k)
      proj = _dot2(v, n_k)
      if proj > apothem + eps:
        problems.append(
          f"ring vertex {index} outside the face planes: "
          f"dot(v, n_{k})={proj:.6f} > apothem {apothem:.6f}"
        )
  return problems


def _corner_bound_problems(ring, apothem, sides, face_width, step, eps):
  """Corner bound (both regimes): a ring vertex standing ON a face plane
  may not cross that face's corner: |dot(v, t_k)| <= faceWidth/2 + eps
  for every face k whose plane the vertex lies on. This is the anti-tip
  assertion — the shipped plane-intersection ring sat exactly on two
  planes (so the prism invariant could not see it) with its tangential
  distance past the face corner: measured +173.2 px at n=3 d=100, +519.6
  px at n=3 d=300. With d < 0 the N-gon vertices sit strictly INSIDE the
  corners and the bound is never tight except at d = 0."""
  problems = []
  for index, (x, _, z) in enumerate(ring, start=1):
    v = (x, z)
    for k in range(sides):
      n_k, t_k = _face_frame(step * k)
      if abs(_dot2(v, n_k) - apothem) > eps:
        continue
      tang = abs(_dot2(v, t_k))
      if tang > face_width / 2 + eps:
        problems.append(
          f"ring vertex {index} beyond face {k} corner: "
          f"|t|={tang:.6f} > faceWidth/2 {face_width / 2:.6f}"
        )
  return problems


def _face_sides_problems(positions, apothem, sides, face_width, step, eps):
  """Face-side clause of the corners regime: every face owns exactly TWO
  ADJACENT ring vertices on its plane, at t = -faceWidth/2 and +faceWidth/2
  EXACTLY (within eps) — the cap covers its face edge to edge, ni mas ni
  menos. With the ring count fixed at 2N this leaves no surplus vertex:
  the leftover edges are necessarily corner-to-corner gap chords."""
  ring = positions[1:]
  problems = []
  for k in range(sides):
    n_k, t_k = _face_frame(step * k)
    on_plane = [
      index
      for index, (x, _, z) in enumerate(ring, start=1)
      if abs(_dot2((x, z), n_k) - apothem) <= eps
    ]
    if len(on_plane) != 2:
      problems.append(
        f"face {k}: {len(on_plane)} ring vertices on its plane, expected exactly 2"
      )
      continue
    first, second = on_plane
    if second - first != 1:
      problems.append(
        f"face {k}: its plane vertices {first} and {second} are not adjacent"
      )
      continue
    lx, _, lz = ring[first - 1]
    rx, _, rz = ring[second - 1]
    t_left = _dot2((lx, lz), t_k)
    t_right = _dot2((rx, rz), t_k)
    if abs(t_left + face_width / 2) > eps or abs(t_right - face_width / 2) > eps:
      problems.append(
        f"face {k}: side ({first}, {second}) off the face corners: "
        f"t={t_left:.6f}, {t_right:.6f} != "
        f"{-face_width / 2:.6f}, {face_width / 2:.6f}"
      )
  return problems


def _gap_chords_problems(positions, apothem, sides, step):
  """Gap clause of the corners regime: every leftover edge is the straight
  chord between face k's right corner and face k+1's left corner, and its
  midpoint projects STRICTLY INSIDE both planes — by construction at
  apothem - d sin^2(pi/N) (measured: -150 px at n=4 d=300). That is where
  the shell shows through the gap: a chord pulled onto the planes would
  tape the hole over and contradicts what the user sees, so reaching the
  plane is rejected. The margin d sin^2(pi/N) is strictly positive for
  every d > 0: over the schema range (CubeFaceDisplacement is a Double
  in [-500, 500], geometryCount <= 36) any displacement at read-back
  resolution (d >= 1 px) leaves >= 7.6e-3 px, ten times the float32
  noise (~7e-4), so the test needs no tolerance — and hand-edited
  sub-0.1 px displacements sit below float32 resolution anyway, where
  the regime itself is indistinguishable.

  Status of the clause: IMPLIED by the face-side exactness, the
  adjacency it enforces and the 2N count — the chord endpoints are
  fully determined, so no mesh reaches this clause first and no
  mesh-level mutation isolates it. It is kept as a cheap DIRECT check
  of the margin the user sees through the gap, and
  _gap_chords_branch_problems pins it from both sides: the closed-form
  margin of the reference ring and a synthetic chord lifted onto the
  plane that this helper itself must report."""
  m = len(positions) - 1
  problems = []
  for k in range(sides):
    right = 2 + 2 * k  # face k's right corner, 1-based positions index
    j = right % m + 1  # the next ring vertex (face k+1's left corner)
    a_pt, b_pt = positions[right], positions[j]
    mid = ((a_pt[0] + b_pt[0]) / 2.0, (a_pt[2] + b_pt[2]) / 2.0)
    for face_index in (k, (k + 1) % sides):
      n_k, _ = _face_frame(step * face_index)
      proj = _dot2(mid, n_k)
      if proj >= apothem:
        problems.append(
          f"gap chord after face {k} covers face {face_index}: "
          f"midpoint projects to {proj:.6f} >= apothem"
        )
  return problems


def _polygon_problems(positions, apothem, sides, face_width, eps):
  """The full polygon-ring contract (ADR-027 amendment), stated per face.

  Runs the hard prism invariant and the corner bound on whatever ring the
  mesh presents, then the structural contract of the regime the apothem
  selects: the inscribed N-gon (midpoint on the apothem + azimuth grid,
  the original _edge_problems clauses) or the face-corner ring (exact
  +/-faceWidth/2 sides + strictly inside gap chords). A ring count that
  matches neither expectation IS the shipped bug: the plane-intersection
  N-gon handed to separated faces."""
  ring = positions[1:]
  m = len(ring)
  step = 2 * math.pi / sides
  half = math.pi / sides
  inscribed = math.atan((face_width / 2) / apothem) >= half - BETA_TOL

  problems = _prism_problems(ring, apothem, sides, step, eps)
  problems.extend(_corner_bound_problems(ring, apothem, sides, face_width, step, eps))

  expected = sides if inscribed else 2 * sides
  if m != expected:
    problems.append(
      f"ring has {m} vertices; the d {'<= 0' if inscribed else '> 0'} "
      f"regime expects {expected}"
    )
    return problems
  if inscribed:
    for k in range(sides):
      problems.extend(
        _edge_problems(
          k,
          positions[1 + k],
          positions[1 + (k + 1) % sides],
          apothem,
          step,
          eps,
        )
      )
  else:
    problems.extend(
      _face_sides_problems(positions, apothem, sides, face_width, step, eps)
    )
    problems.extend(_gap_chords_problems(positions, apothem, sides, step))
  return problems


def validate(
  positions,
  normals,
  uvs,
  indexes,
  r_max,
  ring_count,
  apothem=None,
  sides=None,
  face_width=None,
):
  """Validate one flat cap mesh (polygon when apothem, sides and
  face_width are given together, else disc).

  r_max: the REAL radius of the emitted ring (circumradius of the
  inscribed N-gon, hypot(apothem, faceWidth/2) of the face-corner ring,
  radius of the disc) — the single source the UVs scale on, never derived
  twice. ring_count: number of ring vertices (sides, 2*sides or segments).
  Returns human-readable problems (empty = valid).

  The blocks are private helpers (_check_*) so each one stays simple; the
  order of the extends below IS the order of the checks — every problem
  message is produced by exactly one helper, never re-worded."""
  vertex_count = ring_count + 1
  expected_indexes = ring_count * 3
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
  if apothem is not None and sides is not None and face_width is not None:
    problems.extend(_polygon_problems(positions, apothem, sides, face_width, eps))
  return problems


def reference_polygon(apothem, sides, face_width):
  """Python twin of capPolygonGeometry() — the selftest's healthy ring."""
  alphas, rho, _regime = cap_ring(apothem, sides, face_width)
  m = len(alphas)
  positions = [(0.0, 0.0, 0.0)]
  normals = [(0.0, 1.0, 0.0)]
  uvs = [(0.5, 0.5)]
  for alpha in alphas:
    x = rho * math.sin(alpha)
    z = rho * math.cos(alpha)
    positions.append((x, 0.0, z))
    normals.append((0.0, 1.0, 0.0))
    uvs.append((0.5 + x / (2 * rho), 0.5 + z / (2 * rho)))
  indexes = []
  for i in range(m):
    indexes += [0, 1 + i, 1 + (i + 1) % m]
  return positions, normals, uvs, indexes, rho


def reference_old_polygon(apothem, sides):
  """The PRE-FIX ring: the plane-intersection N-gon regardless of d — the
  exact mesh that shipped the tangential tips, kept to prove the extended
  contract rejects it."""
  step = 2 * math.pi / sides
  r_circ = apothem / math.cos(math.pi / sides)
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


# The corners reference: W = 2560 shared with the inscribed one, N = 4 and
# apothem 1580 — d = +300, the same separated-faces state the user screenshotted.
CORNER_REF = (1580.0, 4, 2560.0)


def _good_mesh_problems(apothem, sides, face_width, radius, segments):
  """All three healthy reference meshes must pass the validator."""
  failures = []
  positions, normals, uvs, indexes, rho = reference_polygon(apothem, sides, face_width)
  problems = validate(
    positions, normals, uvs, indexes, rho, sides, apothem, sides, face_width
  )
  if problems:
    failures.append(f"the reference inscribed polygon did not pass: {problems[0]}")
  positions, normals, uvs, indexes, rho = reference_polygon(*CORNER_REF)
  problems = validate(
    positions,
    normals,
    uvs,
    indexes,
    rho,
    2 * CORNER_REF[1],
    CORNER_REF[0],
    CORNER_REF[1],
    CORNER_REF[2],
  )
  if problems:
    failures.append(f"the reference corners polygon did not pass: {problems[0]}")
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
  # recomputed), so the plane, normal and uv gates stay quiet too. Under
  # the amendment the rotation is FIRST caught by the prism invariant
  # (a vertex on the face azimuth projects rho > apothem), and the
  # midpoint distance and azimuth-grid branches report on the same mesh
  # (|mid - apothem| stays exactly a under a rotation, so within the edge
  # checks it is the grid branch that fires). The two branches stay
  # independently killable via the direct _edge_branch_problems chords.
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
  # n=5, a=1380: edge 0 midpoint |x,z|=1206.164227 against apothem 1380, a
  # 173-unit drop; edge 1 midpoint 1519.86). The vertex stays exactly on
  # the ring radius (the vertices/radius gate is quiet), the plane, the
  # normals and the fan are untouched and the uv follows the vertex, so
  # under the amendment the FIRST problem is the prism invariant (the
  # slid vertex projects past the neighbour plane, rc cos(half - step/8)
  # > apothem); the edge midpoint distance and the azimuth grid report on
  # the same edges afterwards. No mesh-level delta isolates the distance
  # branch alone (any slide big enough for |mid| also moves the midpoint
  # azimuth past the 1e-6 GRID_TOL float32 floor), hence the direct probes
  # _edge_branch_problems below — they keep every branch independently
  # killable.
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


def _mutate_old_geometry(m):
  # The bug that shipped, mesh for mesh: the plane-intersection azimuths
  # (alpha = step*(k+0.5), one vertex per gap — the pre-fix ring's
  # signature) handed to a d > 0 contract that expects the 2N face
  # corners. The ring count alone rejects it; kept on the mesh's own
  # circle so the SIZE clause, not an incidental radius drop, is what
  # answers — the same clause the old N-gon would trip on screen.
  n = (len(m[0]) - 1) // 2
  step = 2 * math.pi / n
  positions, normals, uvs, indexes = [m[0][0]], [m[1][0]], [m[2][0]], []
  for k in range(n):
    alpha = step * (k + 0.5)
    x = m[4] * math.sin(alpha)
    z = m[4] * math.cos(alpha)
    positions.append((x, 0.0, z))
    normals.append((0.0, 1.0, 0.0))
    uvs.append((0.5 + x / (2 * m[4]), 0.5 + z / (2 * m[4])))
  for k in range(n):
    indexes += [0, 1 + k, 1 + (k + 1) % n]
  m[0], m[1], m[2], m[3] = positions, normals, uvs, indexes


def _mutate_corner_slip(m):
  # The user's tips, vertex by vertex: face 0's RIGHT corner slid 150 px
  # along its own face's tangent, past faceWidth/2 — the exact direction
  # the pre-fix rc vertices went (t = rc sin(pi/n) > W/2 for d > 0). The
  # slide keeps dot(v, n_0) == apothem, so the prism invariant stays
  # quiet (that is how the bug escaped every gate that shipped); the ring
  # radius breaks under the chord slide, and the corner bound plus the
  # face-side exactness report the protrusion itself. The direct probe
  # _regime_branch_problems isolates the bound so killing it fails here.
  _n_k, t_k = _face_frame(0.0)
  x, y, z = m[0][2]
  m[0][2] = (x + 150.0 * t_k[0], y, z + 150.0 * t_k[1])
  nx, _, nz = m[0][2]
  r = m[4]
  m[2][2] = (0.5 + nx / (2 * r), 0.5 + nz / (2 * r))


def _mutate_plane_poke(m):
  # The out-of-prism shape the amendment's invariant is named for (the
  # single min()-clamp draft parked the vertex at the plane-intersection
  # azimuth with the corner radius, dot 694.4 against apothem 539.0):
  # here face 0's right corner pulled ALONG THE RING towards the face
  # azimuth 0 (alpha beta -> beta/2), staying on the circle, on the
  # plane y=0, inside the corner tangentially, with a consistent uv — so
  # only the prism invariant (and the exactness of the face side it
  # leaves) can see it. Winding stays CCW: the ring gaps stay < pi.
  r = m[4]
  x, y, z = m[0][2]
  alpha = math.atan2(x, z) / 2.0
  x2 = r * math.sin(alpha)
  z2 = r * math.cos(alpha)
  m[0][2] = (x2, y, z2)
  m[2][2] = (0.5 + x2 / (2 * r), 0.5 + z2 / (2 * r))


# The classic breakages plus the amendment's regressions: one mutation per
# entry, labels verbatim in the log. Each entry is (label, mutate, shapes).
# "cap not inscribed" and "cap edge off the apothem" are inscribed-only; the
# three corners-only entries reproduce the ADR-027 amendment's bug families
# (the shipped N-gon under d > 0, the tangential tip past the face corner
# and the out-of-prism vertex). The disc contract fixes radius, fan and
# centred uvs but NEVER the azimuth (measured: a half-step-rotated disc and
# a one-vertex-slid disc both validate clean — another rotation/slide of a
# rotationally symmetric drum is still a valid drum), so shape-crossings on
# the disc would prove nothing. With this table the selftest reports 17
# detections: 6 mesh breakages x 2 shapes + 2 inscribed-only + 3 corners-
# only; the healthy-mesh checks and the six branch probes print no PASS
# line (they only fail when their gate is not isolated).
MUTATIONS = [
  ("NaN vertex", _mutate_nan_vertex, ("polygon", "disc")),
  ("inverted winding", _mutate_flip, ("polygon", "disc")),
  ("uv out of range", _mutate_bad_uv, ("polygon", "disc")),
  ("index out of range", _mutate_bad_index, ("polygon", "disc")),
  ("missing triangle", _mutate_missing_triangle, ("polygon", "disc")),
  ("cap not inscribed", _mutate_half_step, ("polygon",)),
  ("uv not centred", _mutate_uv_squeezed, ("polygon", "disc")),
  ("cap edge off the apothem", _mutate_off_radius_midpoint, ("polygon",)),
  ("pre-fix N-gon under d > 0", _mutate_old_geometry, ("corners",)),
  ("cap tip beyond the face corner", _mutate_corner_slip, ("corners",)),
  ("cap vertex outside the face planes", _mutate_plane_poke, ("corners",)),
]


def _broken_mesh_problems(kind, mutate, apothem, sides, face_width, radius, segments):
  """Apply one mutation to a fresh reference mesh and re-validate it."""
  if kind == "polygon":
    ref = reference_polygon(apothem, sides, face_width)
    poly = (apothem, sides, face_width)
  elif kind == "corners":
    ref = reference_polygon(*CORNER_REF)
    poly = CORNER_REF
  else:
    ref = reference_disc(radius, segments)
    poly = None
  broken = [list(ref[0]), list(ref[1]), list(ref[2]), list(ref[3]), ref[4]]
  mutate(broken)
  if poly is None:
    return validate(broken[0], broken[1], broken[2], broken[3], broken[4], segments)
  a, n, w = poly
  expected_ring = len(cap_ring(a, n, w)[0])
  return validate(
    broken[0],
    broken[1],
    broken[2],
    broken[3],
    broken[4],
    expected_ring,
    a,
    n,
    w,
  )


def _edge_branch_problems():
  """Isolate the two _edge_problems branches with direct synthetic chords.

  A full ring slide can never exercise ONLY the apothem-distance branch:
  any delta moving |mid| past eps (measured threshold: 3.4e-6 rad) also
  displaces the midpoint azimuth by delta/2, over the GRID_TOL = 1e-6 rad
  grid tolerance (the float32 read-back floor of a real ring) — so with
  the distance gate disabled the mesh-level cases would still be caught
  by the grid branch and a green selftest would not prove the distance
  gate runs. These two chords do:
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
  chord = _edge_problems(0, (r_circ, 0.0, 0.0), (-r_circ, 0.0, 0.0), apothem, step, eps)
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


def _regime_branch_problems():
  """Isolate the amendment's two per-face gates with direct vertices.

  No single slipped ring vertex can separate them at mesh level (a corner
  outside the prism also leaves its face side; the mesh-level regressions
  above are deliberately multi-gate), so each gate gets its own synthetic
  vertex that only it must see: a vertex OUT of the prism along the face
  normal but tangentially inside the corner (the min()-clamp shape) must
  raise exactly the plane problem and stay quiet on the corner bound (it
  is on no plane); a vertex ON a plane but PAST its corner (the shipped
  tip shape) must raise exactly the corner problem and stay quiet on the
  plane invariant (it projects exactly apothem). Killing either gate
  fails exactly these assertions and the selftest exits non-zero."""
  apothem, sides, face_width = CORNER_REF
  step = 2 * math.pi / sides
  rho = math.hypot(apothem, face_width / 2)
  eps = 1e-6 * max(1.0, rho)
  n_k, t_k = _face_frame(0.0)
  failures = []
  # (apothem + 150) along face 0's normal, 640 along its tangent: outside
  # the prism, inside the corner, on no face plane.
  poked = (
    (apothem + 150.0) * n_k[0] + (face_width / 4) * t_k[0],
    0.0,
    (apothem + 150.0) * n_k[1] + (face_width / 4) * t_k[1],
  )
  prism = _prism_problems([poked], apothem, sides, step, eps)
  bound = _corner_bound_problems([poked], apothem, sides, face_width, step, eps)
  if len(prism) != 1 or "outside the face planes" not in prism[0]:
    failures.append(f"plane invariant not isolated: {prism}")
  if bound:
    failures.append(f"plane poke leaked into the corner bound: {bound}")
  # Exactly apothem along face 0's normal, corner + 150 along its tangent:
  # the shipped-tip shape — on the plane (the prism invariant cannot see
  # it, which is how the bug escaped) but past the face corner.
  tip = (
    apothem * n_k[0] + (face_width / 2 + 150.0) * t_k[0],
    0.0,
    apothem * n_k[1] + (face_width / 2 + 150.0) * t_k[1],
  )
  prism = _prism_problems([tip], apothem, sides, step, eps)
  bound = _corner_bound_problems([tip], apothem, sides, face_width, step, eps)
  if prism:
    failures.append(f"corner tip leaked into the plane invariant: {prism}")
  if len(bound) != 1 or "beyond face" not in bound[0]:
    failures.append(f"corner bound not isolated: {bound}")
  return failures


def _face_sides_branch_problems():
  """Isolate the EXACTNESS of _face_sides_problems with one synthetic ring.

  No mesh-level mutation can isolate it: a corner slid OUT past W/2 is
  caught by the corner bound first (it runs earlier in _polygon_problems)
  and also leaves the ring circle, so neutering the exactness clause
  left every other detection untouched — measured during the ADR-027
  amendment's kill review. The isolating shape is the SHRUNK face: both
  face-0 corners stay exactly ON its plane (the prism invariant is
  quiet), keep their adjacency and the 2N count, but their tangential
  distance is pulled IN symmetrically to +/- (W/2 - delta) with
  delta = 0.02 * face_width (the corner bound is quiet because
  |t| < W/2). Only the exactness clause protests: the cap would cover
  its face edge delta short on BOTH sides. A mesh mutation cannot
  express the same state without also breaking the ring-radius gate
  first (a circle of radius rho crosses each plane at exactly t =
  +/-W/2), which is why this is a direct probe in the style of
  _edge_branch_problems. The reverse case (the untouched reference
  corners ring) must stay clean under the same clause. Neutering
  _face_sides_problems fails the first assertion and the selftest
  exits non-zero; neutering the OTHER gates keeps this probe green,
  so each clause dies alone."""
  apothem, sides, face_width = CORNER_REF
  step = 2 * math.pi / sides
  rho = math.hypot(apothem, face_width / 2)
  eps = 1e-6 * max(1.0, rho)
  n_k, t_k = _face_frame(0.0)
  delta = 0.02 * face_width
  positions, _normals, _uvs, _indexes, _r = reference_polygon(*CORNER_REF)
  shrunk = list(positions)
  for slot, sign in ((1, -1.0), (2, 1.0)):
    t = sign * (face_width / 2 - delta)
    shrunk[slot] = (
      apothem * n_k[0] + t * t_k[0],
      0.0,
      apothem * n_k[1] + t * t_k[1],
    )
  failures = []
  exact = _face_sides_problems(shrunk, apothem, sides, face_width, step, eps)
  if len(exact) != 1 or "corners" not in exact[0]:
    failures.append(f"face-side exactness not isolated: {exact}")
  if _prism_problems(shrunk[1:], apothem, sides, step, eps):
    failures.append("shrunk face leaked into the plane invariant")
  if _corner_bound_problems(shrunk[1:], apothem, sides, face_width, step, eps):
    failures.append("shrunk face leaked into the corner bound")
  clean = _face_sides_problems(positions, apothem, sides, face_width, step, eps)
  if clean:
    failures.append(f"exact reference faces not quiet: {clean}")
  return failures


def _gap_chords_branch_problems():
  """The gap-chord clause is IMPLIED — said so honestly, kept killable.

  With the ring count fixed at 2N and every face owning exactly two
  adjacent vertices on its plane at t = +/-W/2, the chord endpoints are
  fully determined and their midpoints project to exactly
  apothem - d sin^2(pi/N) < apothem (measured: -150 px on the corners
  reference). No mesh can violate the chord clause without first
  violating the face-side exactness or the count, so
  _gap_chords_problems is kept as a cheap DIRECT check of the margin
  the user sees through the gap rather than an independent regime gate
  — but it must not rot into a dead clause, and this probe pins both
  halves:

    (1) the reference ring's chord midpoints match the closed-form
        margin exactly (a drifted generator or reference trips HERE
        even while every clause stays quiet);
    (2) the healthy reference ring must come back clean from the
        helper, and one corner raised LIFT px along its own plane
        normal — lifting the following chord's midpoint above the face
        plane — must make the helper itself report exactly one
        problem.

  An overridden, always-quiet _gap_chords_problems passes (1) but dies
  on (2); a corrupted plane comparison dies the same way. LIFT exceeds
  2 * margin because the chord midpoint only moves half of the raised
  vertex."""
  apothem, sides, face_width = CORNER_REF
  step = 2 * math.pi / sides
  half = math.pi / sides
  rho = math.hypot(apothem, face_width / 2)
  eps = 1e-6 * max(1.0, rho)
  displacement = apothem - (face_width / 2) / math.tan(half)
  positions, _normals, _uvs, _indexes, _r = reference_polygon(*CORNER_REF)
  m = len(positions) - 1
  want = apothem - displacement * math.sin(half) ** 2
  failures = []
  # (1) closed-form margin on every chord of the reference ring.
  for k in range(sides):
    right = 2 + 2 * k
    j = right % m + 1
    a_pt, b_pt = positions[right], positions[j]
    mid = ((a_pt[0] + b_pt[0]) / 2.0, (a_pt[2] + b_pt[2]) / 2.0)
    for face_index in (k, (k + 1) % sides):
      n_k, _ = _face_frame(step * face_index)
      proj = _dot2(mid, n_k)
      if abs(proj - want) > 10 * eps:
        failures.append(
          f"chord after face {k} misses the margin identity on "
          f"face {face_index}: {proj:.6f} != {want:.6f}"
        )
  # (2a) the healthy ring is clean for the helper itself.
  quiet = _gap_chords_problems(positions, apothem, sides, step)
  if quiet:
    failures.append(f"reference chords not quiet: {quiet}")
  # (2b) a chord lifted onto the plane MUST be reported by the helper.
  lift = 2.0 * displacement * math.sin(half) ** 2 + 50.0
  n_k, _ = _face_frame(0.0)
  raised = list(positions)
  x, _, z = raised[2]  # face 0's right corner, 1-based positions index
  raised[2] = (x + lift * n_k[0], 0.0, z + lift * n_k[1])
  covering = _gap_chords_problems(raised, apothem, sides, step)
  if len(covering) != 1 or "covers" not in covering[0]:
    failures.append(f"gap-chord clause not isolated: {covering}")
  return failures


def selftest():
  """The validator must pass the healthy meshes and reject every breakage.

  Coverage = the three healthy references (inscribed N-gon, face-corner
  ring, disc) + 11 mesh-level mutations (17 PASS detections: 6 x both
  classical shapes, 2 inscribed-only, 3 corners-only) + the six direct
  branch probes that keep _edge_problems' midpoint gates, the prism
  invariant, the corner bound, the face-side exactness and the implied
  gap-chord margin independently killable."""
  apothem, sides, face_width = 1380.0, 5, 2560.0
  radius, segments = 1693.4, 64
  failures = _good_mesh_problems(apothem, sides, face_width, radius, segments)
  failures.extend(_edge_branch_problems())
  failures.extend(_regime_branch_problems())
  failures.extend(_face_sides_branch_problems())
  failures.extend(_gap_chords_branch_problems())

  for kind in ("polygon", "corners", "disc"):
    for name, mutate, shapes in MUTATIONS:
      if kind not in shapes:
        continue
      label = f"{kind}: {name}"
      found = _broken_mesh_problems(
        kind, mutate, apothem, sides, face_width, radius, segments
      )
      if not found:
        failures.append(f"{label} was NOT detected")
      else:
        print(f"  PASS detects {label}: {found[0]}")

  return selftest_verdict("check-cap", failures)
