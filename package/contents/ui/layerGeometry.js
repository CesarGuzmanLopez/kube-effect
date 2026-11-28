/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Window-layer geometry (ADR-028, model H): the pure depth formulas behind
// WindowLayers.qml and the Cube LOD gate, plus the kwinrc clamps for the
// four WindowLayer* keys.
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
// so every depth is applied as -z (inwards, never outwards — quads pushed
// outside crossed walls and neighbouring faces in the earlier exploration
// and that design is discarded). One face unit is one pixel: the quads use
// the "#Rectangle" primitive (100 units) scaled by size/100, the same
// convention as the flat face itself — no extra /100, or every window would
// pile at the centre of the face.

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
// ever sinks further, no matter how many windows a face holds.
const LAYER_DEPTH_CAP = 150;
// Every quad sits this much BEHIND its computed depth, so no layer ever
// lands exactly on z = 0, the face plane itself. With WindowLayerGap 0 all
// the layers share this minimal depth (the flat-parity case, gate (e)).
const LAYER_EPSILON = 0.01;
// The plate sits this much behind the deepest layer (never in front of it:
// a veil before the top layer would cover the windows it should back).
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

// The depth budget of one face. Solids (polygon >= 3 faces, drum) keep the
// stack within half the way to the centre, so a quad can never pass the
// middle of the solid; the flat sheet (ADR-024) has no walls behind it and
// its faceDistance is a few-pixel gap, so it gets the cap directly (measured:
// the solid formula would crush the sheet stack to ~1 px). A non-finite
// distance (mid-sync geometry) gets the cap too, never NaN depths.
function maxLayerDepth(isSheet, faceDistance, cap) {
  const budget = finiteOr(cap);
  const limit = budget === null ? LAYER_DEPTH_CAP : Math.max(0, budget);
  if (isSheet === true) {
    return limit;
  }
  const distance = finiteOr(faceDistance);
  if (distance === null) {
    return limit;
  }
  return Math.max(0, Math.min(distance * 0.5, limit));
}

// The step actually used between two consecutive ranks: the configured gap,
// SMALLER when the whole stack would not fit the budget. Repartitioning one
// common (smaller) step keeps the strict rank order and lands the deepest
// layer exactly on maxLayerDepth — clamping per layer instead would flatten
// the deep ones onto one plane and lose their order (ARQUITECTURA 2.4, the
// trap). A gap that already fits is never stretched to fill the budget.
function fittedGap(gap, maxDepth, maxRank) {
  const rank = finiteOr(maxRank);
  const steps = Math.max(1, rank === null ? 1 : Math.floor(rank));
  const depth = finiteOr(maxDepth);
  const budget = depth === null ? 0 : Math.max(0, depth);
  return Math.min(gapUnits(gap), budget / steps);
}

// The depth of one layer, measured from the TOP of the stack: the front-most
// window (rank == maxRank) sits at 0 (just behind the face, at -epsilon),
// every rank below sinks one fitted step further.
function layerDepth(maxRank, rank, gap) {
  const top = finiteOr(maxRank);
  const mine = finiteOr(rank);
  const step = finiteOr(gap);
  if (top === null || mine === null || step === null) {
    return 0;
  }
  return (top - mine) * step;
}

// Where the plate sits, behind the deepest layer. NEVER in front of it.
function plateDepth(maxDepth) {
  const depth = finiteOr(maxDepth);
  return (depth === null ? 0 : Math.max(0, depth)) + PLATE_DEPTH_EXTRA;
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
