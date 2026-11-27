/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Cap mesh generators (ADR-027): the pure geometry behind CapMesh.qml, kept
// out of constants.js so one file holds one responsibility (the helper
// module had already outgrown its budget before the ADR-027 amendment added
// the face-corner branch). Both generators follow the same contract as the
// arc mesh: the surface lies in the XZ plane (y = 0) centred on the node
// origin, normals are (0, 1, 0), the fan winds CCW seen from +Y, and the
// UVs are centred on the ring radius. The +/- halfHeight offset belongs to
// the NODE, so ONE flat mesh serves both caps: the bottom cap is the same
// geometry on a node rotated 180 deg, never a second mesh.
//
// scripts/check-cap.py validates these rules offscreen against the real
// ProceduralMesh; check-constants.qml exercises the helpers directly.

// Finite test with the same coercion as the historical isFinite(): KConfig
// values can arrive as strings, so Number() first (the constants.js rule,
// kept local because QML script files do not import each other).
function isFiniteNumber(value) {
  return Number.isFinite(Number(value));
}

// Azimuth band where the face-corner and the plane-intersection vertices
// coincide. Exactly at d = 0 the float rounding of faceDistance can push
// betaFace a single ulp below halfStep (measured: n = 4 with W = 2560 gives
// atan(1280 / 1280.0000000000002) < pi/4), and the corner branch would then
// emit two almost-duplicate ring vertices and a sliver triangle. Treating
// betaFace >= halfStep - 1e-9 rad as equality collapses that case onto the
// N-gon: ONE vertex where the two corner vertices used to merge.
const CAP_BETA_TOL = 1e-9;

// Cap ring of the POLYGON solid: the vertices sit on the real FACE CORNERS,
// not on the intersection of the face planes (ADR-027 amendment). The old
// ring used rc = apothem / cos(pi/n) — the distance where two consecutive
// face planes meet. That coincides with a face corner only while the faces
// touch (CubeFaceDisplacement d <= 0); for d > 0 the binding constraint is
// the half width of the face, and the intersection vertex sticks out of the
// face tangentially as a tip past the corner (measured with W = 2560:
// +173.2 px at n=3 d=100, +519.6 px at n=3 d=300, +100.0 px at n=4 d=100,
// +72.7 px at n=5 d=100 — the protruding points the user saw on screen).
// faceWidth is the input that was missing: without it the cap could only
// follow the planes and never knew where the face ends.
//
// Two explicit branches. A single beta = min(betaFace, halfStep) clamp is
// NOT enough: with negative d it keeps the vertex at the intersection
// azimuth but at the corner radius, projecting PAST the face planes
// (measured at n=3 d=-200: 694.4 against the apothem 539.0 — the cap would
// poke through the walls, the mirror failure of the bug being fixed).
//
//   a        = apothem (the live faceDistance, the one geometric source)
//   step     = 2*pi/n;  halfStep = pi/n;  w = faceWidth
//   betaFace = atan((w/2) / a)             azimuth of a real face corner
//
//   betaFace >= halfStep - tol (d <= 0): the face reaches past the plane
//   intersection -> inscribed N-gon, identical to the original ADR-027 ring:
//     rho       = a / cos(halfStep)        (n vertices)
//     alpha(k)  = step * (k + 0.5)         edge midpoints on azimuth step*k,
//                                          exactly where Cube.faceAzimuth
//                                          places the faces.
//   betaFace <  halfStep (d > 0): face corners + straight gap chords:
//     rho       = hypot(a, w/2)            (2n vertices)
//     per face k: alpha = step*k +/- betaFace; the ring azimuths increase
//     strictly (betaFace < halfStep keeps step*k + betaFace below
//     step*(k+1) - betaFace), so the fan (0, i, i+1) stays CCW with no
//     duplicated vertex and no degenerate triangle.
//
//   The branches agree exactly at d = 0 (betaFace == halfStep implies
//   hypot(a, w/2) == a / cos(halfStep); measured difference <= 2.3e-13 px),
//   so sliding the displacement past zero shows no jump, and for d < 0 the
//   ring is the virgin N-gon (zero visual regression).
//
//   normal = (0, 1, 0)                     CCW seen from +Y is the top
//                                          cap's outward side; the bottom
//                                          cap flips it through its node
//                                          rotation.
//   uv     = (0.5 + x/(2 rho), 0.5 + z/(2 rho))  centred on the REAL ring
//                                          radius of each branch — every
//                                          ring vertex sits on that circle,
//                                          so the UVs stay inside [0, 1].
//
// Invariants the generator guarantees (asserted per vertex in each face's
// LOCAL frame by check-cap.py — never against a world-axis max, which is
// false: the correct n=3 d=300 ring has max |x| = 1539.8 > w/2): no ring
// vertex may project past any face plane, dot(v, n_k) <= a, and none may
// stand tangentially further out than its own face's corner,
// |dot(v, t_k)| <= w/2. The gap chords between consecutive face corners
// lie INSIDE the planes (their midpoint projects to exactly a - d *
// sin^2(pi/n)), so the shell keeps showing through the gap — the cap seals
// the faces, not the holes.
//
// Degenerate input answers EMPTY arrays (the cylinderArcGeometry contract):
// apothem <= 0 or faceWidth <= 0 happen for transient states and for a
// hand-edited displacement past the apothem (ADR-022 range), sides < 3 is
// not a polygon, and a non-finite halfHeight means faceSize has not settled
// yet — mid-sync renders nothing instead of a floating NaN plane.
function capPolygonGeometry(apothem, faceWidth, sides, halfHeight) {
  const a = Number(apothem);
  const w = Number(faceWidth);
  const rawSides = Number(sides);
  const h = Number(halfHeight);
  if (
    !isFiniteNumber(a) ||
    a <= 0 ||
    !isFiniteNumber(w) ||
    w <= 0 ||
    !isFiniteNumber(h) ||
    h <= 0 ||
    !isFiniteNumber(rawSides) ||
    Math.floor(rawSides) < 3
  ) {
    return { positions: [], normals: [], uvs: [], indexes: [] };
  }
  const n = Math.floor(rawSides);
  const step = (2 * Math.PI) / n;
  const halfStep = Math.PI / n;
  const betaFace = Math.atan(w / 2 / a);

  const alphas = [];
  let rho;
  if (betaFace >= halfStep - CAP_BETA_TOL) {
    // d <= 0: the inscribed N-gon of the original ADR-027 (n vertices,
    // every edge midpoint on a face plane and on the face azimuth grid).
    rho = a / Math.cos(halfStep);
    for (let k = 0; k < n; ++k) {
      alphas.push(step * (k + 0.5));
    }
  } else {
    // d > 0: two vertices per face, the real corners (a, +/- w/2) in the
    // face's local frame. n >= 3 keeps halfStep <= pi/3 and betaFace
    // finite, so rho = hypot(a, w/2) is finite and positive.
    rho = Math.hypot(a, w / 2);
    for (let k = 0; k < n; ++k) {
      alphas.push(step * k - betaFace, step * k + betaFace);
    }
  }
  const m = alphas.length;

  const positions = [];
  const normals = [];
  const uvs = [];
  const indexes = [];

  // Vertex 0 is the centre; the fan is (0, 1 + i, 1 + (i + 1) mod m),
  // CCW seen from +Y for increasing azimuth (same outward convention as
  // the arc mesh).
  positions.push(Qt.vector3d(0, 0, 0));
  normals.push(Qt.vector3d(0, 1, 0));
  uvs.push(Qt.vector2d(0.5, 0.5));
  for (let i = 0; i < m; ++i) {
    const x = rho * Math.sin(alphas[i]);
    const z = rho * Math.cos(alphas[i]);
    positions.push(Qt.vector3d(x, 0, z));
    normals.push(Qt.vector3d(0, 1, 0));
    uvs.push(Qt.vector2d(0.5 + x / (2 * rho), 0.5 + z / (2 * rho)));
  }
  for (let i = 0; i < m; ++i) {
    indexes.push(0, 1 + i, 1 + ((i + 1) % m));
  }

  return { positions: positions, normals: normals, uvs: uvs, indexes: indexes };
}

// Disc of radius `radius` in the XZ plane (y = 0), fan-triangulated from the
// centre: the cap of the cylinder at any count, drum or three-slot drum
// (ADR-027: it closes the empty wedges too). Same conventions as
// capPolygonGeometry — derived nothing (R is already the single source),
// normals +Y, CCW seen from +Y, centred UVs, one flat mesh shared by both
// caps through a node rotation. `segments` follows the arc mesh (64, fixed),
// so the disc silhouette matches the drum it closes. Degenerate input
// (radius <= 0, non-finite halfHeight, fewer than 3 segments) answers EMPTY
// arrays, exactly like the arc generator's mid-sync rule.
function capDiscGeometry(radius, segments, halfHeight) {
  const r = Number(radius);
  const rawSegments = Number(segments);
  const h = Number(halfHeight);
  if (
    !isFiniteNumber(r) ||
    r <= 0 ||
    !isFiniteNumber(h) ||
    h <= 0 ||
    !isFiniteNumber(rawSegments) ||
    Math.floor(rawSegments) < 3
  ) {
    return { positions: [], normals: [], uvs: [], indexes: [] };
  }
  const s = Math.floor(rawSegments);
  const step = (2 * Math.PI) / s;

  const positions = [];
  const normals = [];
  const uvs = [];
  const indexes = [];

  positions.push(Qt.vector3d(0, 0, 0));
  normals.push(Qt.vector3d(0, 1, 0));
  uvs.push(Qt.vector2d(0.5, 0.5));
  for (let k = 0; k < s; ++k) {
    // No half-step offset: a disc is rotationally symmetric, its ring
    // needs no alignment with the face azimuths (unlike the polygon).
    const x = r * Math.sin(step * k);
    const z = r * Math.cos(step * k);
    positions.push(Qt.vector3d(x, 0, z));
    normals.push(Qt.vector3d(0, 1, 0));
    uvs.push(Qt.vector2d(0.5 + x / (2 * r), 0.5 + z / (2 * r)));
  }
  for (let k = 0; k < s; ++k) {
    indexes.push(0, 1 + k, 1 + ((k + 1) % s));
  }

  return { positions: positions, normals: normals, uvs: uvs, indexes: indexes };
}
