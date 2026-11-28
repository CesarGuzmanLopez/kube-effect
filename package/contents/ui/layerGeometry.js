/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Window-layer geometry (ADR-028 model H as amended 2026-11-27): the pure
// depth formulas behind WindowLayers.qml and the Cube LOD gate, plus the
// kwinrc clamps for the five WindowLayer* keys.
//
// This module lives apart from constants.js on purpose, exactly like
// arcGeometry.js and capGeometry.js (the ADR-027 precedent): constants.js
// keeps the VALUE resolvers for everything that predates the layers, while
// the layer math — a single responsibility of its own — is self-contained so
// scripts/check-layers.py can validate the depths against an independent
// Python oracle without loading the scene. QML scripts cannot import each
// other, so the finite guard is carried per module (the same copy the other
// two modules make); scripts/check-constants.qml pins every copy to the SAME
// string-coercion behaviour as constants.js.
//
// Conventions (ARQUITECTURA 2.4): +z on the face node is the OUTWARD normal,
// and the amended model pushes the stack OUTWARDS: inwards was measured in
// the nested session (2026-11-27) and the face holes then showed the INSIDE
// of the solid (white wedges of far quads/faces, the mirrored "ABA" label),
// with the windows reading as sunken into the cube. Outwards is the desk
// metaphor: the WHOLE stack floats outwards — the bottom of the pile
// starts one fitted step off the face and the top window is the CLOSEST to
// the observer (measured the other way: rank 0 parked at bare +epsilon
// read as "the bottom window is glued to the desktop all the time").
// There are no inner walls to protect any more, so
// the budget is the fixed cap for EVERY shape (the old per-representation
// min(faceDistance * 0.5, cap) is retired) and the holes of the face grab
// (they stay — without a hole the flat window and its quad would double)
// are veiled by the plate just behind the face plane. The earlier
// exploration's rejection of outward quads ("crossing walls") does not
// apply here: that model had no holes and no veil. One face unit is one
// pixel: the quads use the "#Rectangle" primitive (100 units) scaled by
// size/100, the same convention as the flat face itself — no extra /100, or
// every window would pile at the centre of the face.

// Finite test with the same coercion as the historical isFinite(): KConfig
// values can arrive as strings and Number.isFinite() would reject them. The
// local Number() coercion is kept inside this one place so no call site has
// to remember the difference (identical to the constants.js copy).
function isFiniteNumber(value) {
  return Number.isFinite(Number(value));
}

// Number(null) and Number("") are 0, not NaN: a KConfig value that was never
// saved (null/empty) would otherwise clamp to the RANGE FLOOR instead of the
// schema default (the ADR-022 trap, same rule as constants.js.finiteOr).
function finiteOr(nullable) {
  if (nullable === null || nullable === undefined) {
    return null;
  }
  if (typeof nullable === "string" && nullable.trim() === "") {
    return null;
  }
  const value = Number(nullable);
  return Number.isFinite(value) ? value : null;
}

// Hard cap of the whole stack in px (the 150 px budget of ADR-028): no layer
// ever travels further out, no matter how many windows a face holds. Since
// the amendment this is the budget for EVERY shape — outward stacking has no
// inner walls to protect, so the per-representation formula disappeared.
const LAYER_DEPTH_CAP = 150;
// Every quad sits this much IN FRONT of its computed depth, so no layer ever
// lands exactly on z = 0, the face plane itself. With the whole stack
// floating (the third amendment) even the bottom layer is one fitted step
// ahead of this plane; only WindowLayerGap 0 collapses every layer onto
// this minimal depth (the flat-parity case, gate (e)).
const LAYER_EPSILON = 0.01;
// The plate sits this much BEHIND the face plane (z = -PLATE_DEPTH_EXTRA):
// just behind the grab, in front of the solid's interior. Its job is to veil
// the face holes so the inside of the cube never shows through them, and it
// is always behind every quad (the quads start at +step+epsilon, +epsilon
// only when the gap is 0).
const PLATE_DEPTH_EXTRA = 2;
// The dark veil colour behind the whole stack (WindowLayerPlateOpacity only
// scales it); it is visible through the face holes and nothing else.
const PLATE_COLOR = "#141719";
// Resolvers for the raw kwinrc entries (same rule as the constants.js
// resolvers: an unset or hand-edited garbage value falls back to the schema
// DEFAULT, never to the range floor, and everything else is clamped).
const GAP_DEFAULT = 120;
const GAP_MIN = 0;
const GAP_MAX = 600;
const LOD_FACES_DEFAULT = 1;
const LOD_FACES_MIN = 0;
const LOD_FACES_MAX = 8;
const PLATE_OPACITY_DEFAULT = 0.25;
// WindowLayerRotationOpacity (Double 0-1): the ABSOLUTE opacity of the pile
// while the cube moves. 0.7 is the schema default and equals the face
// rotation default (FaceRotationOpacity), so the turn fade matches the
// face out of the box; 1.0 keeps the windows solid WHILE TURNING too (the
// depth-ordered Mask stays on). At rest the layers are ALWAYS 1 (opaque
// windows) — ScreenView feeds this value as the rotation branch of
// Constants.faceOpacity(1, resolved, cubeMoving), the very mechanism and
// duration (FaceFadeMs) the faces already use, zero new machinery. The 0.1
// fade floor of Constants.faceOpacity applies while rotating, same as the
// faces; the flag off makes the whole key inert (no quads exist at all).
const ROTATION_OPACITY_DEFAULT = 0.7;

function clamped(raw, minimum, maximum, fallback) {
  const value = finiteOr(raw);
  if (value === null) {
    return fallback;
  }
  return Math.min(maximum, Math.max(minimum, value));
}

// WindowLayerGap (Int 0-600 px): the requested depth step per stacking rank.
// 0 is a real value (every layer shares the epsilon depth), so only an
// unset/non-finite entry uses the schema default.
function gapUnits(rawGap) {
  return clamped(rawGap, GAP_MIN, GAP_MAX, GAP_DEFAULT);
}

// WindowLayerLodFaces (Int 0-8): how many faces around the current desktop
// instantiate quads; 0 means ALL of them. Rounded: it indexes faces.
function lodFaces(rawLod) {
  return Math.round(clamped(rawLod, LOD_FACES_MIN, LOD_FACES_MAX, LOD_FACES_DEFAULT));
}

// WindowLayerPlateOpacity (Double 0-1): the veil alpha; 0 is a real
// "no veil" value, exactly like the capOpacity contract.
function plateOpacity(rawOpacity) {
  return clamped(rawOpacity, 0, 1, PLATE_OPACITY_DEFAULT);
}

// WindowLayerRotationOpacity (Double 0-1): the absolute layer opacity while
// rotating; 0 clamps UP through Constants.faceOpacity's 0.1 fade floor at
// the call site (the same face rule), so the raw 0..1 range is passed
// through here and an unset/non-finite entry uses the schema default.
function rotationOpacity(rawOpacity) {
  return clamped(rawOpacity, 0, 1, ROTATION_OPACITY_DEFAULT);
}

// The step actually used between two consecutive ranks: the configured gap,
// SMALLER when the whole stack would not fit the cap. The stack occupies
// maxRank + 1 STEPS (the bottom layer floats one step off the plane — the
// third amendment; parking it on the bare epsilon read as "the bottom
// window is glued to the desktop"): repartitioning one common (smaller)
// step keeps the strict rank order and lands the outermost layer exactly on
// the cap — clamping per layer instead would flatten the outer ones onto one
// plane and lose their order (ARQUITECTURA 2.4, the trap). The budget is the
// fixed cap for every shape (amendment: outward stacking crosses no walls,
// so the old per-representation maxLayerDepth became dead code and was
// removed). A gap that already fits is never stretched to fill the cap.
function fittedGap(gap, maxRank) {
  const rank = finiteOr(maxRank);
  const steps = Math.max(1, (rank === null ? 1 : Math.floor(rank)) + 1);
  return Math.min(gapUnits(gap), LAYER_DEPTH_CAP / steps);
}

// The depth of one layer, measured OUTWARDS from the face plane: rank is the
// number of windows of this face with a SMALLER stackingOrder. The whole
// stack floats: rank 0 (the bottom of the pile) sits one fitted step off the
// face, the top window (rank == maxRank) is the outermost — exactly at the
// cap + epsilon when the stack does not fit (with a single window and a gap
// that does not fit: exactly at the cap too). The epsilon keeps every quad
// strictly in front of z = 0, the face plane; gap 0 puts them ALL on
// +epsilon (flat parity, gate (e)).
function layerDepthOut(rank, step) {
  const mine = finiteOr(rank);
  const gap = finiteOr(step);
  if (mine === null || gap === null) {
    return LAYER_EPSILON;
  }
  return (mine + 1) * gap + LAYER_EPSILON;
}

// Where the plate sits: a magnitude of PLATE_DEPTH_EXTRA BEHIND the face
// plane (callers negate it: z = -2). It veils the face holes — never in
// front of any quad (those start at +epsilon), never deep enough to be
// reached by the interior geometry either.
function plateDepth() {
  return PLATE_DEPTH_EXTRA;
}

// The LOD gate (ADR-028 rule 3): distance of a face INDEX to the current
// desktop's face, wrapped on the ring (the drum's empty slots and the sheet
// share the same index distance). lod <= 0 answers true for every face; an
// unresolvable current index (-1 mid-sync) answers false, so a face without
// a known centre never pays captures it cannot order.
function layerWithinLod(index, currentFaceIndex, faceCount, lod) {
  const budget = finiteOr(lod);
  if (budget === null || budget <= 0) {
    return true;
  }
  const i = finiteOr(index);
  const cur = finiteOr(currentFaceIndex);
  const count = finiteOr(faceCount);
  if (i === null || cur === null || cur < 0 || count === null || count <= 0) {
    return false;
  }
  const raw = Math.abs(i - cur);
  const dist = Math.min(raw, count - raw);
  return dist <= Math.round(budget);
}
