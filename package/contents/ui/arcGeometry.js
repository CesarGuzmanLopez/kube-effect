/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Cylinder arc generator (ADR-025/ADR-026): the pure mesh data behind
// CylinderArcMesh.qml.
//
// This module lives apart from constants.js on purpose, exactly like
// capGeometry.js (the ADR-027 precedent): constants.js keeps the VALUE
// resolvers (enums, ranges, opacities, radii formulas), while the geometry
// generators — the functions that emit positions/normals/uvs/indexes — are
// self-contained so a mesh holder can load only what it needs. QML scripts
// cannot import each other, so the finite guard is carried per module (the
// same copy capGeometry.js makes); scripts/check-constants.qml pins both.
//
// The REAL output of this generator is validated offscreen by
// scripts/check-cylinder.py (cylindricity around the node-local axis,
// isometric UVs, arc length = W, radial normals, CCW winding) and its
// wiring into Cube.qml by scripts/check-cylinder-wiring.py — this file is
// deliberately free of KWin and scene imports so both can run headless.

// Finite test with the same coercion as the historical isFinite(): KConfig
// values can arrive as strings and Number.isFinite() would reject them. Every
// helper here reads a raw kwinrc entry, so the finite guard must accept "50"
// exactly as the global isFinite did; the local Number() coercion is kept
// inside this one place so no call site has to remember the difference.
function isFiniteNumber(value) {
  return Number.isFinite(Number(value));
}

// Fallback segment count for a garbage `segments` argument: kept in sync
// with CYLINDER_SEGMENTS in constants.js (the "segments fixed" case in
// scripts/check-constants.qml pins that value to 64; every runtime call
// site passes it explicitly).
const FALLBACK_SEGMENTS = 64;

// Vertex data of ONE face-arc, generated around ITS OWN NODE: the arc's
// mid-point sits at the origin and the drum axis at (0, 0, -R), so placing
// the face is exactly the polygon rule — position = rotate(azimuth) *
// (0, 0, faceDistance=R) plus eulerRotation.y = azimuth (ADR-026). The old
// mesh lived centred on +Z with every node pinned to (0, 0, 0): all the
// faces then shared one sort centroid and QtQuick3D's transparent-pass
// ordering (world bounds centre -> view depth, qssglayerrenderdata.cpp)
// lost a reliable key for the drum; the polygon never had that problem
// because each Model already carries its own position. phi0 is NOT baked
// into the mesh, which is what lets all faces still share one geometry.
// Returns {positions, normals, uvs, indexes} in the shape ProceduralMesh
// wants (lists of Qt.vector3d / Qt.vector2d / uint), for arc-length s in
// [0, W] and height t in [0, H]:
//
//   phi(s)    = (s - W/2) / R            arc symmetric about +Z, mid at 0
//   P(s, t)   = (R sin phi, t - H/2, R cos phi - R)
//   normal(s) = (sin phi, 0, cos phi)    radial, pointing OUT of the axis
//   uv(s, t)  = (s / W, t / H)           v = 0 at the bottom row (y = -H/2)
//
// The v convention was MEASURED, not assumed: decoding Qt 6.12's own
// Rectangle.mesh shows the built-in #Rectangle carries (u, v) = (0, 0) at
// (x, y) = (-50, -50) and (1, 1) at (50, 50) — bottom-left origin — so the
// same Texture { sourceItem } that paints a polygon face upright paints the
// arc upright (winding is likewise CCW seen from outside, like the
// rectangle's own 0,1,2 order).
//
// Degenerate input (a zero/garbage width, height or radius — transiently
// possible while the model syncs) answers EMPTY arrays: a ProceduralMesh
// with no positions renders nothing, which is the safe mid-sync state.
function cylinderArcGeometry(faceWidth, faceHeight, radius, segments) {
  const width = Number(faceWidth);
  const height = Number(faceHeight);
  const r = Number(radius);
  if (
    !isFiniteNumber(width) ||
    !isFiniteNumber(height) ||
    !isFiniteNumber(r) ||
    width <= 0 ||
    height <= 0 ||
    r <= 0
  ) {
    return { positions: [], normals: [], uvs: [], indexes: [] };
  }
  const rawSegments = Number(segments);
  const segs = isFiniteNumber(rawSegments)
    ? Math.max(1, Math.floor(rawSegments))
    : FALLBACK_SEGMENTS;

  const positions = [];
  const normals = [];
  const uvs = [];
  const indexes = [];

  for (let i = 0; i <= segs; ++i) {
    // Column i sits at arc-length s = W*i/segs, centred: phi runs from
    // -theta/2 to +theta/2 with theta = W/R.
    const phi = ((width * i) / segs - width / 2) / r;
    const sine = Math.sin(phi);
    const cosine = Math.cos(phi);
    // Two vertices per column: bottom (v = 0) then top (v = 1), so the
    // indexes of a column are (2i, 2i + 1).
    positions.push(
      Qt.vector3d(r * sine, -height / 2, r * cosine - r),
      Qt.vector3d(r * sine, height / 2, r * cosine - r),
    );
    normals.push(Qt.vector3d(sine, 0, cosine), Qt.vector3d(sine, 0, cosine));
    uvs.push(Qt.vector2d(i / segs, 0), Qt.vector2d(i / segs, 1));
  }

  for (let i = 0; i < segs; ++i) {
    const a = 2 * i; //     bottom, column i
    const b = a + 1; //     top,    column i
    const c = a + 2; //     bottom, column i + 1
    const d = a + 3; //     top,    column i + 1
    // Cross products of both triangles point along the radial (outward)
    // normal: seen from OUTSIDE the cylinder each triangle runs
    // counter-clockwise, the same convention as #Rectangle's mesh.
    indexes.push(a, c, b, b, c, d);
  }

  return { positions: positions, normals: normals, uvs: uvs, indexes: indexes };
}
