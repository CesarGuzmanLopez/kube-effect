#!/usr/bin/env python3
"""Pure oracle for the window layers (ADR-028, model H as amended 2026-11-27),
stdlib only.

check-layers.py instantiates the REAL Cube.qml (and through it CubeFace,
WindowLayers, DesktopView and the extended stub WindowFilterModel) in an
offscreen engine, dumps the live quads/grab/plate as JSON and validates
everything here against an INDEPENDENT re-derivation of the amended ADR-028
formulas — the cap_contract.py pattern for the caps. The oracle never trusts
the engine for the math: expected depths, ranks, fitted steps, holes and the
plate position are recomputed from the mirrored kwinrc clamps plus the FIXED
cap (the amendment pushes the stack outwards, so there is no per-shape
budget left to mirror).

Clause families (the five innegociable asserts of the ADR-028 "Puertas",
updated by the amendment):
  (a) strict monotony: z STRICTLY INCREASING with rank and POSITIVE (the
      top window is the outermost; no two layers of a face coplanar);
  (b) budget: the WHOLE stack floats (third amendment: z = (rank + 1) *
      fitted + epsilon — rank 0 one step off the face, never parked on the
      bare epsilon while the gap is positive), every (rank+1)*fitted <=
      cap and a stack that does not fit lands the OUTERMOST layer EXACTLY
      on cap (maxRank + 1 steps span the budget; one fitted step for all,
      no per-layer clamp, no stretch when the configured gap already fits)
      — the same fixed cap for every shape, sheet included;
  (h) slab box (fourth amendment, final single-box design): eff =
      min(request clamped 0-300 with default 24, fitted/2) decides the
      shape. eff 0 (or no QtQuick3D.Helpers) -> flat built-in #Rectangle,
      NoCulling front, unit z scale: pixel parity with the quad-only
      model. eff > 0 -> ONE closed ProceduralMesh box per layer: TWO
      material subsets (0 = textured front, 1 = sides + back edge colour
      - the subset order is BUILT in SlabMesh.qml, not guessed from Qt
      docs, because Model has no customMaterials in 6.12: verified
      against the live engine), scale (win.w/100, win.h/100, eff/100) so
      the box spans the EXACT window rect, the node CENTRED at
      ladder - eff/2 so the FRONT lands exactly on the ladder (cap and
      no-crossing measured at the front), z scale eff/100 (a request
      beyond half the step is CLIPPED, never obeyed), both materials
      BackFaceCulling (NoCulling was the measured black bezel through
      the thumbnail's transparent shadow margins), the front keeping its
      WindowThumbnail map and both materials sharing the threshold and
      opacity; consecutive ranks satisfy back(rank n+1) >= front(rank n):
      two layers never intersect.
  (c) LOD off and flag off: zero quads instantiated and the grab keeps
      every internalId (pixel parity with the cube of before);
  (d) every id in layeredIds has wId == "" in its face grab, and every id
      NOT layered (minimized/dock/desktopWindow) keeps its internalId;
  (i) lighting (measured 2026-11-28: an unlit edge band reads as a shadow,
      not a solid): the edge material is Fragment-lit with the pinned
      roughness/metalness while the front, the faces and the plate keep
      the ADR-026 NoLighting; and the camera headlight exists iff
      WindowLayering does (a Repeater3D with model 0 instantiates zero
      nodes - the virgin tree of the flag-off cube is byte-for-byte the
      old one, lights included);
  (e) gap 0: every layer of a face shares z == +epsilon;
  (f) plate: z == -2 (the veil just behind the face plane), strictly behind
      EVERY quad (-2 < +epsilon) so it veils the holes without covering
      the windows;
  (g) material contract (the ORDER amendment, measured 2026-11-27: a quad's
      sort centroid carries the window's lateral offset and does NOT follow
      the rank — the opaque pass fixes it): with the pile effectively opaque
      (layerOpacity >= 0.99: at rest, or WindowLayerRotationOpacity 1.0
      while turning) every shown quad is Mask with alphaCutoff pinned at
      0.5 and material opacity == layerOpacity; below the threshold it is
      Blend with the same opacity (the turn fade, ADR-021 pattern with the
      pile's own key). The plate is Blend ALWAYS (uniform veil, nothing to
      order) with opacity == resolved(plate) x layerOpacity. And the two
      parity clauses the user confirmed: (g1) flag OFF makes
      WindowLayerRotationOpacity inert at ANY value (0.2/0.7/1.0 tested):
      zero quads, zero layeredIds, the grab intact, and the live FACE
      materials still follow ONLY faceOpacity (never layerOpacity —
      without layers the windows are pixels of the grab and share the
      desktop's transparency); (g2) flag ON at rest (faceOpacity 1, not
      rotating) gives every shown quad opacity 1 and Mask — a layered
      window looks exactly like the flat window it replaces, hole aside.
      The rotation resolver parity is numeric too: expected layerOpacity
      while turning is Constants.faceOpacity(1, resolved(key), true),
      i.e. the same value the face fade answers with the same key (the
      default 0.7 equals FaceRotationOpacity's default: parity by
      construction).

Stub window layout (mirrored from qml_check_harness.STUB_MODULE; keep the
two in sync when the stub changes): desktop n has rows i = 0..5 with
internalId "stub-<n>-<i>", stackingOrder i, x = 100+150i, y = 80+120i,
width = 320-40i, height = 200+30i; i=3 minimized, i=4 dock, i=5
desktopWindow. The ordinary rows 0..2 must win quads; 3..5 must never.
"""

import sys

# The layerGeometry.js constants (a drift fails the gate, the point of
# mirroring them here). CAP is the budget for EVERY shape since the
# amendment (outward stack, no inner walls to protect); PLATE_EXTRA is the
# magnitude of the veil's offset BEHIND the face plane (plate z = -2).
CAP = 150.0
EPSILON = 0.01
PLATE_EXTRA = 2
GAP_MIN, GAP_MAX, GAP_DEFAULT = 0, 600, 120
LOD_MIN, LOD_MAX, LOD_DEFAULT = 0, 8, 1
PLATE_MIN, PLATE_MAX, PLATE_DEFAULT = 0.0, 1.0, 0.25
ROT_MIN, ROT_MAX, ROT_DEFAULT = 0.0, 1.0, 0.7
# The fade floor of constants.js Constants.faceOpacity (MIN_FACE_OPACITY):
# the layer chain reuses that machinery (rest=1, rotation=this key), so
# while turning the value also floors at 0.1 — the same rule the faces
# already follow. A drift here fails the gate against check-constants.py.
FADE_FLOOR = 0.1
MASK_THRESHOLD = 0.99
FACE_CUTOFF = 0.5
# Edge lighting (measured 2026-11-28): the unlit flat colour "reads as a
# shadow, not a solid" - the edge material is Fragment-lit (rough matte
# plastic) and the camera headlight exists iff the layers do; everything
# else in the effect keeps the ADR-026 NoLighting contract.
EDGE_LIGHTING = "fragment"
EDGE_ROUGHNESS = 0.7
EDGE_METALLIC = 0.0
UNLIT = "none"
# Slab (fourth amendment, final single-box design): the thickness request
# clamps 0-300 with a default of 24 (measured 2026-11-28: with the previous
# default 2 the box was built but the rim never read; 24 finally looks like
# a solid at oblique angles; 0 stays a real value: flat quad, pixel parity);
# the EFFECTIVE value is then clipped to half the fitted step, so two
# layers can never intersect. The edge colour defaults to the plate tone;
# anything the QML resolver maps to the default must map to the same rgba
# here.
THICK_MIN, THICK_MAX, THICK_DEFAULT = 0, 300, 24
EDGE_DEFAULT_HEX = "#141719"
# Tolerance for the edge colour components (float32 round-trip of a hex
# colour through the live material).
EDGE_TOL = 1e-5

STUB_ROWS = 6
STUB_SHOWN = (0, 1, 2)
STUB_DROPPED = (3, 4, 5)
STUB_COUNT = 3


# Node positions are float32 in the scene graph (QtQuick3D stores
# position/vector3d as single precision), so every comparison that reads a
# position back carries a float32 tolerance; pure double bindings
# (fittedGap, the resolved budget) keep the tight one.
POSITION_TOL = 1e-3


def close(actual, expected, tolerance=1e-6):
  return abs(float(actual) - float(expected)) <= tolerance


def resolved_gap(raw):
  try:
    value = float(raw)
  except (TypeError, ValueError):
    return float(GAP_DEFAULT)
  return min(GAP_MAX, max(GAP_MIN, value))


def resolved_lod(raw):
  try:
    value = float(raw)
  except (TypeError, ValueError):
    return float(LOD_DEFAULT)
  value = min(LOD_MAX, max(LOD_MIN, value))
  return round(value)


def resolved_plate(raw):
  try:
    value = float(raw)
  except (TypeError, ValueError):
    return PLATE_DEFAULT
  return min(PLATE_MAX, max(PLATE_MIN, value))


def resolved_rotation(raw):
  # layerGeometry.rotationOpacity: unset/non-finite -> the SCHEMA DEFAULT
  # (0.7), never the range floor (the ADR-022 rule the other resolvers obey).
  try:
    value = float(raw)
  except (TypeError, ValueError):
    return ROT_DEFAULT
  return min(ROT_MAX, max(ROT_MIN, value))


def resolved_thickness(raw):
  try:
    value = float(raw)
  except (TypeError, ValueError):
    return float(THICK_DEFAULT)
  return min(THICK_MAX, max(THICK_MIN, value))


def expected_effective(raw, fitted):
  """layerGeometry.thicknessEffective: the request clipped to half the
  fitted step (the step per face; the cap/overflow repartition can shrink
  it, and the clip follows it down)."""
  return min(resolved_thickness(raw), max(0.0, float(fitted)) / 2)


def edge_rgba(raw):
  """Mirror of layerGeometry.edgeColor + Qt's hex parsing, reduced to the
  forms the schema/KCM produce (#rrggbb, #rgb; anything else the QML
  resolver maps to the default string, mirrored here as the default rgba).
  Returns (r, g, b, a) floats."""
  value = raw.strip() if isinstance(raw, str) else ""
  if len(value) >= 4 and value[0] == "#":
    digits = value[1:]
    try:
      if len(digits) == 3:
        r, g, b = (int(c * 2, 16) / 255.0 for c in digits)
        return (r, g, b, 1.0)
      if len(digits) == 6:
        r = int(digits[0:2], 16) / 255.0
        g = int(digits[2:4], 16) / 255.0
        b = int(digits[4:6], 16) / 255.0
        return (r, g, b, 1.0)
    except ValueError:
      pass
  digits = EDGE_DEFAULT_HEX[1:]
  return (
    int(digits[0:2], 16) / 255.0,
    int(digits[2:4], 16) / 255.0,
    int(digits[4:6], 16) / 255.0,
    1.0,
  )


def expected_layer_opacity(rotating, raw):
  # ScreenView's chain, mirrored: Constants.faceOpacity(1, resolved, moving)
  # -> rest is hard-wired 1 (solid windows at rest, clause (g2)); while
  # turning, the key's value floored by the shared 0.1 fade floor.
  if not rotating:
    return 1.0
  return min(1.0, max(FADE_FLOOR, resolved_rotation(raw)))


def expected_fitted_gap(gap, max_rank):
  # The stack occupies maxRank + 1 steps (the bottom floats one step off
  # the plane - the third amendment), so the fitted step divides the cap by
  # maxRank + 1 and the TOP layer lands exactly on cap when it does not fit.
  steps = max(1, int(max_rank) + 1)
  return min(gap, CAP / steps)


def layer_depth_out(rank, fitted):
  """Mirror of layerGeometry.layerDepthOut: the whole stack floats, one
  step per rank counting rank 0, plus the epsilon off the plane."""
  return (rank + 1) * fitted + EPSILON


def lod_distance(index, current, face_count):
  raw = abs(int(index) - int(current))
  return min(raw, int(face_count) - raw)


def _face_context(face, dump):
  """The mirrored per-face values every clause group needs (no checks here)."""
  layering = bool(dump["layering"])
  lod = resolved_lod(dump.get("lodRaw"))
  gap = resolved_gap(dump.get("gapRaw"))
  plate = resolved_plate(dump.get("plateRaw"))
  current = int(dump["currentFaceIndex"])
  layer = expected_layer_opacity(
    bool(dump.get("rotating")), dump.get("layerRotationRaw")
  )
  face_opacity = float(dump["faceOpacityLive"])
  return {
    "label": f"face {face['index']} (desktop {face['desktopNumber']})",
    "layering": layering,
    "lod": lod,
    "gap": gap,
    "plate": plate,
    "layer": layer,
    "face_opacity": face_opacity,
    "thickness_raw": dump.get("thicknessRaw"),
    "edge_raw": dump.get("edgeRaw", "#141719"),
    "helpers": bool(dump.get("helpersInstalled", True)),
    "current": current,
    "expect_active": layering
    and (
      lod <= 0
      or (
        current >= 0 and lod_distance(face["index"], current, dump["faceCount"]) <= lod
      )
    ),
    "grab_by_id": {row["id"]: row["wId"] for row in face["grabs"]},
    "expected_grab_ids": {
      f"stub-{face['desktopNumber']}-{i}" for i in range(STUB_ROWS)
    },
  }


def _active_problems(ctx, face, problems):
  """Cube mirror of the LOD decision: the gate does not only check depths,
  a diverging Cube/WindowLayers flag would pass math computed against the
  mirror while the scene used another one. (The budget mirror died with the
  amendment: the cap is a module constant now, pinned above.)"""
  if bool(face["active"]) is not ctx["expect_active"]:
    problems.append(
      f"{ctx['label']}: active {face['active']}, expected {ctx['expect_active']} (flag {ctx['layering']}, lod {ctx['lod']}, current {ctx['current']})"
    )


def _grab_rows_problems(ctx, problems):
  label = ctx["label"]
  if set(ctx["grab_by_id"]) != ctx["expected_grab_ids"]:
    problems.append(
      f"{label}: grab rows {sorted(ctx['grab_by_id'])} != stub rows {sorted(ctx['expected_grab_ids'])}"
    )


def _inactive_face_problems(ctx, face, problems):
  """(c) + pixel parity: no quad, no hole, plate hidden."""
  label = ctx["label"]
  if face["quads"]:
    problems.append(
      f"{label}: inactive face still instantiates quads: {[q['id'] for q in face['quads']]}"
    )
  if face["layeredIds"]:
    problems.append(
      f"{label}: inactive face still publishes layeredIds: {face['layeredIds']}"
    )
  for win_id, w_id in ctx["grab_by_id"].items():
    if w_id != win_id:
      problems.append(
        f"{label}: grab released {win_id} (wId={w_id!r}) with no layering"
      )
  if face["plateVisible"]:
    problems.append(f"{label}: plate visible on an inactive face")


def _holes_problems(ctx, face, problems):
  """(d) layered ids == the shown stub rows, and the hole is exact: layered
  ids released, dropped ids kept flat in the grab (a hole without a quad is
  a hole in the shell)."""
  label = ctx["label"]
  expected_layered = {f"stub-{face['desktopNumber']}-{i}" for i in STUB_SHOWN}
  if set(face["layeredIds"]) != expected_layered:
    problems.append(
      f"{label}: layeredIds {sorted(face['layeredIds'])} != shown rows {sorted(expected_layered)}"
    )
  for win_id in expected_layered:
    if ctx["grab_by_id"].get(win_id) != "":
      problems.append(
        f"{label}: layered {win_id} not released from the grab (wId={ctx['grab_by_id'].get(win_id)!r})"
      )
  for i in STUB_DROPPED:
    win_id = f"stub-{face['desktopNumber']}-{i}"
    if ctx["grab_by_id"].get(win_id) != win_id:
      problems.append(
        f"{label}: dropped {win_id} released from the grab anyway (wId={ctx['grab_by_id'].get(win_id)!r}) — hole without a quad"
      )


def _quad_sets_problems(ctx, face, problems):
  """Shown/hidden split of the repeater and the per-quad invariants. The
  repeater holds ONE delegate per row (a QML model cannot be filtered
  without a proxy): only the showLayer ones render, the dropped rows must
  exist INVISIBLE with the thumbnail released. Returns the shown quads, or
  None when the set itself is wrong (depth checks would only cascade)."""
  label = ctx["label"]
  quads = face["quads"]
  shown = [q for q in quads if q["showLayer"]]
  hidden = [q for q in quads if not q["showLayer"]]
  expected_ids = sorted(f"stub-{face['desktopNumber']}-{i}" for i in STUB_SHOWN)
  found_ids = sorted(q["id"] for q in shown)
  if found_ids != expected_ids:
    problems.append(f"{label}: shown quads {found_ids} != expected {expected_ids}")
    return None
  expected_hidden = sorted(ctx["expected_grab_ids"] - {q["id"] for q in shown})
  found_hidden = sorted(q["id"] for q in hidden)
  if found_hidden != expected_hidden:
    problems.append(
      f"{label}: hidden quads {found_hidden} != dropped rows {expected_hidden}"
    )
  for quad in hidden:
    if quad["visible"]:
      problems.append(
        f"{label}: dropped row {quad['id']} renders a quad (a hole-filler outside the stack)"
      )
  for quad in shown:
    _shown_quad_problems(label, quad, problems)
  return shown


def _shown_quad_problems(label, quad, problems):
  if not quad["visible"]:
    problems.append(f"{label}: quad {quad['id']} hidden while the face layers")
  if not quad["pickable"]:
    problems.append(f"{label}: quad {quad['id']} is not pickable")
  if not quad["desktopOk"]:
    problems.append(
      f"{label}: quad {quad['id']} does not re-expose the face desktop (click must switchTo the face's desktop)"
    )


def _depths_problems(ctx, face, dump, shown, problems):
  """maxRank/fittedGap mirrors plus every quad's z on the fitted outward
  ladder, its cap bound and its window-centre coincidence. Returns the
  depth map the stack-shape clause needs."""
  label = ctx["label"]
  orders = sorted(q["order"] for q in shown)
  if orders != list(STUB_SHOWN):
    problems.append(
      f"{label}: quad orders {orders} != stub stacking {list(STUB_SHOWN)}"
    )
  max_rank = len(shown) - 1
  if int(face["maxRank"]) != max_rank:
    problems.append(
      f"{label}: maxRank {face['maxRank']} != {max_rank} (dropped rows must not enter the rank map)"
    )
  gap = ctx["gap"]
  fitted = expected_fitted_gap(gap, max_rank)
  if not close(face["fittedGap"], fitted):
    problems.append(f"{label}: fittedGap {face['fittedGap']} != mirrored {fitted}")

  depths = {}
  for quad in shown:
    rank = sum(1 for other in orders if other < quad["order"])
    depths[quad["id"]] = (rank + 1) * fitted
    _quad_depth_problems(label, quad, rank, fitted, dump, problems)
  return {
    "depths": depths,
    "fitted": fitted,
    "max_rank": max_rank,
    "orders": orders,
    "eff": expected_effective(dump.get("thicknessRaw"), fitted),
  }


def _quad_depth_problems(label, quad, rank, fitted, dump, problems):
  """One quad on the ladder: exact outward z ((rank + 1) * fitted +
  epsilon - the WHOLE stack floats: the bottom one step off the face, the
  top the outermost), never past the cap, strictly IN FRONT of the face
  plane, centred over its own window (the hole and the quad coincide;
  local px, Y flips)."""
  depth = (rank + 1) * fitted
  # With the box the NODE sits centred eff/2 behind the ladder (the front
  # lands back on it); flat layers sit ON it. The mirror follows the
  # dump's own mode so a scene that stays flat when the eff demands a box
  # is caught by the (h) clause, not hidden here.
  box_shift = (
    expected_effective(dump.get("thicknessRaw"), fitted) / 2
    if quad.get("boxMode") == "box"
    else 0.0
  )
  expected_z = depth + EPSILON - box_shift
  if not close(quad["z"], expected_z, POSITION_TOL):
    problems.append(
      f"{label}: quad {quad['id']} z {quad['z']} != {expected_z} (rank {rank}, fitted {fitted})"
    )
  # (b) every layer within the budget (never past the cap).
  if depth > CAP + 1e-9:
    problems.append(f"{label}: quad {quad['id']} depth {depth} exceeds the cap {CAP}")
  if quad["z"] < EPSILON - 1e-9:
    problems.append(
      f"{label}: quad {quad['id']} is not strictly in front of the face plane (z {quad['z']})"
    )
  i = int(quad["id"].rsplit("-", 1)[1])
  center_x = 100 + 150 * i + (320 - 40 * i) / 2 - dump["faceWidth"] / 2
  center_y = dump["faceHeight"] / 2 - (80 + 120 * i + (200 + 30 * i) / 2)
  if not close(quad["x"], center_x, POSITION_TOL):
    problems.append(
      f"{label}: quad {quad['id']} x {quad['x']} != window centre {center_x}"
    )
  if not close(quad["y"], center_y, POSITION_TOL):
    problems.append(
      f"{label}: quad {quad['id']} y {quad['y']} != window centre {center_y}"
    )


def _stack_shape_problems(ctx, shown, ladder, problems):
  """(a) strict rank monotony, z growing OUTWARDS with rank + (b) the
  exact-cap landing of a non-fitting stack (and no stretch for a fitting
  one) + (e) the gap-0 +epsilon parity."""
  label = ctx["label"]
  gap = ctx["gap"]
  fitted = ladder["fitted"]
  max_rank = ladder["max_rank"]
  if fitted <= 0:
    # (e) gap 0: every layer shares the +epsilon plane (flat parity).
    for quad in shown:
      if not close(quad["z"], EPSILON):
        problems.append(
          f"{label}: zero gap put {quad['id']} at z {quad['z']}, expected {EPSILON}"
        )
    return
  # (a) strict monotony by rank: the top window (max order) is the
  # OUTERMOST quad (largest z) and no two layers ever share a plane.
  zs = sorted((q["order"], q["z"]) for q in shown)
  for k in range(1, len(zs)):
    if zs[k][1] <= zs[k - 1][1] + 1e-9:
      problems.append(f"{label}: layers not strictly ordered outwards by rank: {zs}")
  # A stack that does not fit MUST land exactly on the cap (repartido, no
  # per-layer clamp): maxRank + 1 fitted steps span the whole budget, so
  # the outermost quad (max rank) reaches CAP.
  if gap * (max_rank + 1) > CAP + 1e-9:
    outermost = max(ladder["depths"].values())
    if not close(outermost, CAP, POSITION_TOL):
      problems.append(
        f"{label}: non-fitting stack outermost depth {outermost} != cap {CAP}"
      )
  # A gap that fits is never stretched to fill the cap.
  if gap * (max_rank + 1) <= CAP and not close(fitted, gap):
    problems.append(f"{label}: fitting gap {gap} was stretched to {fitted}")


def _plate_problems(ctx, face, shown, problems):
  """(f) The veil sits at z = -PLATE_EXTRA, just behind the face plane: it
  must stay STRICTLY BEHIND EVERY quad (they start at +epsilon — a plate in
  front of the bottom layer would cover the windows it should veil), and it
  only shows while its alpha is on (multiplied by the face opacity
  downstream)."""
  label = ctx["label"]
  if not close(face["plateZ"], -PLATE_EXTRA, POSITION_TOL):
    problems.append(
      f"{label}: plate z {face['plateZ']} != -{PLATE_EXTRA} (the veil plane just behind the face)"
    )
  for quad in shown:
    if face["plateZ"] >= quad["z"]:
      problems.append(
        f"{label}: plate z {face['plateZ']} is in front of quad {quad['id']} (z {quad['z']}) — it must veil the holes, not cover the windows"
      )
  if bool(face["plateVisible"]) is not (ctx["plate"] > 0.001):
    problems.append(
      f"{label}: plate visible {face['plateVisible']} with plateOpacity {ctx['plate']}"
    )


def _face_material_problems(ctx, face, problems):
  """(g1) Parity of the FACE material - read live from the engine, flag off
  or on, at any rotation value: it follows ONLY faceOpacity (and the shape
  rules), never layerOpacity. With no layers the windows are pixels of the
  grab, so the desktop's transparency IS the windows' transparency.
  The harness builds plain polygon faces (cylinderMesh null), where
  CubeFace.qml pins Blend at every opacity; a Mask here would mean the
  layer machinery touched the face material."""
  label = ctx["label"]
  if face["faceAlphaMode"] != "blend":
    problems.append(
      f"{label}: face material alphaMode {face['faceAlphaMode']!r} - the plain face must stay Blend (the face rule, never driven by the layer keys)"
    )
  if not close(face["faceOpacityLive"], ctx["face_opacity"]):
    problems.append(
      f"{label}: face material opacity {face['faceOpacityLive']} != faceOpacity {ctx['face_opacity']} (the face fade must stay its own)"
    )
  # The cutoff the face pins explicitly (ADR-026): a drift means somebody
  # rewired the face material block.
  if not close(face["faceCutoffLive"], FACE_CUTOFF):
    problems.append(
      f"{label}: face alphaCutoff {face['faceCutoffLive']} != pinned {FACE_CUTOFF}"
    )
  if face.get("faceLighting", "none") != UNLIT:
    problems.append(
      f"{label}: face material lighting {face.get('faceLighting')!r} != none (the ADR-026 grab contract: faces are never re-illuminated by the headlight)"
    )


def _quad_lighting_problems(label, quad, problems):
  """Clause (i): the front never receives light (the textured grab
  contract, ADR-026) while the edge MUST be Fragment-lit with the pinned
  matte roughness (measured 2026-11-28: an unlit edge is a shadow-like
  contour, no volume)."""
  if quad.get("frontLighting") != UNLIT:
    problems.append(
      f"{label}: quad {quad['id']} front lighting {quad.get('frontLighting')!r} != none (the textured front stays NoLighting)"
    )
  if quad.get("edgeLighting") != EDGE_LIGHTING:
    problems.append(
      f"{label}: quad {quad['id']} edge lighting {quad.get('edgeLighting')!r} != {EDGE_LIGHTING!r} (an unlit edge reads as a flat shadow, not a solid)"
    )
  if not close(quad.get("edgeRoughness", 0.0), EDGE_ROUGHNESS):
    problems.append(
      f"{label}: quad {quad['id']} edge roughness {quad.get('edgeRoughness')} != {EDGE_ROUGHNESS} (matte plastic, never a mirror)"
    )
  if not close(quad.get("edgeMetallic", 1.0), EDGE_METALLIC):
    problems.append(
      f"{label}: quad {quad['id']} edge metallic {quad.get('edgeMetallic')} != {EDGE_METALLIC}"
    )


def _plate_material_problems(ctx, face, problems):
  """(g) The plate stays Blend ALWAYS (uniform veil, nothing to order) and
  fades with the pile: opacity == resolved(plate) x layerOpacity, read
  live from the engine."""
  label = ctx["label"]
  if face["plateAlphaMode"] != "blend":
    problems.append(
      f"{label}: plate alphaMode {face['plateAlphaMode']!r} - the veil must stay Blend always"
    )
  if face.get("plateLighting", "none") != UNLIT:
    problems.append(
      f"{label}: plate lighting {face.get('plateLighting')!r} != none (the veil is a flat colour by design)"
    )
  expected = ctx["plate"] * ctx["layer"]
  if not close(face["plateOpacityLive"], expected):
    problems.append(
      f"{label}: plate opacity {face['plateOpacityLive']} != plateOpacity x layerOpacity = {ctx['plate']} x {ctx['layer']} = {expected}"
    )


def _quad_material_problems(ctx, shown, problems):
  """(g)+(g2) The quad threshold over the EFFECTIVE pile opacity: at rest
  (layerOpacity 1 by construction) every shown quad is Mask, cutoff pinned,
  opacity 1 - a layered window looks exactly like the flat window it
  replaces, hole aside (the user-confirmed rest parity). While turning
  below the threshold: Blend with opacity == the fade value (== what the
  face machinery answers for the same key, so the 0.7 default parities the
  face out of the box). At or above it (key 1.0): Mask ALSO while turning -
  solid windows, depth-ordered."""
  label = ctx["label"]
  layer = ctx["layer"]
  expected = "mask" if layer >= MASK_THRESHOLD else "blend"
  for quad in shown:
    if quad["alphaMode"] != expected:
      problems.append(
        f"{label}: quad {quad['id']} alphaMode {quad['alphaMode']!r} != {expected!r} for layerOpacity {layer} (>= {MASK_THRESHOLD} means the depth-ordered Mask)"
      )
    _quad_lighting_problems(label, quad, problems)
    if not close(quad["materialOpacity"], layer):
      problems.append(
        f"{label}: quad {quad['id']} material opacity {quad['materialOpacity']} != layerOpacity {layer}"
      )
    if expected == "mask" and not close(quad["alphaCutoff"], FACE_CUTOFF):
      problems.append(
        f"{label}: quad {quad['id']} alphaCutoff {quad['alphaCutoff']} != pinned {FACE_CUTOFF} while Mask"
      )


def _slab_problems(ctx, shown, ladder, problems):
  """(h) The single closed box (fourth amendment, final design): eff =
  min(request, fitted/2) decides. Split per case for readability (S3776):
  _slab_rect_problems is the flat parity, _slab_box_problems the boxed
  layer; both share the window-rect scale check."""
  label = ctx["label"]
  eff = ladder["eff"]
  helpers = ctx["helpers"]
  ordered = sorted(shown, key=lambda q: q["z"])
  previous_front = None
  for quad in ordered:
    _slab_rect_problems(label, quad, problems)
    if eff <= 1e-12 or not helpers:
      # Flat (or the documented degradation without QtQuick3D.Helpers):
      # the node sits ON the ladder, there is no front offset.
      previous_front = quad["z"]
      _slab_flat_case(label, quad, eff, helpers, problems)
      continue
    previous_front = _slab_box_case(label, quad, eff, ctx, previous_front, problems)


def _slab_rect_problems(label, quad, problems):
  """The box - flat or not - spans the EXACT window rect in x/y (a fatter
  box is the bezel bug in geometry form: the shadow margins must not be
  part of the slab)."""
  i = int(quad["id"].rsplit("-", 1)[1])
  expect_w = (320 - 40 * i) / 100
  expect_h = (200 + 30 * i) / 100
  if not close(quad["scaleX"], expect_w, POSITION_TOL) or not close(
    quad["scaleY"], expect_h, POSITION_TOL
  ):
    problems.append(
      f"{label}: layer {quad['id']} x/y scale {quad['scaleX']}x{quad['scaleY']} != window {expect_w}x{expect_h} (box larger than the window)"
    )


def _slab_flat_case(label, quad, eff, helpers, problems):
  """eff 0 (or no Helpers): the built-in #Rectangle with NoCulling and a
  unit z scale - pixel parity with the quad-only model."""
  if quad["boxMode"] != "flat":
    problems.append(
      f"{label}: {quad['id']} renders the box with effective thickness {eff} and helpers={helpers} (flat parity broken)"
    )
  if not close(quad["scaleZ"], 1.0, POSITION_TOL):
    problems.append(
      f"{label}: {quad['id']} flat layer carries a z scale {quad['scaleZ']} (the #Rectangle stays 2D)"
    )


def _slab_box_case(label, quad, eff, ctx, previous_front, problems):
  """eff > 0 with Helpers: the two-subset closed box. Returns the front
  plane for the caller's no-crossing walk."""
  layer = ctx["layer"]
  expected_mode = "mask" if layer >= MASK_THRESHOLD else "blend"
  edge = edge_rgba(ctx["edge_raw"])
  if quad["boxMode"] != "box" or int(quad["boxSubsets"]) != 2:
    problems.append(
      f"{label}: {quad['id']} is not the two-subset box (mode {quad['boxMode']!r}, subsets {quad['boxSubsets']}) with eff {eff}"
    )
  if not close(quad["scaleZ"], eff / 100, POSITION_TOL):
    problems.append(
      f"{label}: {quad['id']} box z scale {quad['scaleZ']} != eff/100 = {eff / 100} (request beyond half the step must be CLIPPED)"
    )
  if quad["frontCull"] != "back" or quad["edgeCull"] != "back":
    problems.append(
      f"{label}: {quad['id']} box cull {quad['frontCull']!r}/{quad['edgeCull']!r} != back/back (NoCulling on a closed box shows its inner side through the shadow margins: the measured black bezel)"
    )
  if not quad["frontHasMap"]:
    problems.append(f"{label}: {quad['id']} box front lost its WindowThumbnail map")
  if quad["edgeAlphaMode"] != expected_mode:
    problems.append(
      f"{label}: edge material alphaMode {quad['edgeAlphaMode']!r} != {expected_mode!r} (same threshold as the front, never fixed)"
    )
  if not close(quad["edgeOpacity"], layer):
    problems.append(
      f"{label}: edge material opacity {quad['edgeOpacity']} != layerOpacity {layer}"
    )
  for want, got in zip(
    edge, (quad["edgeR"], quad["edgeG"], quad["edgeB"], quad["edgeA"])
  ):
    if not close(got, want, EDGE_TOL):
      problems.append(
        f"{label}: edge colour component {got} != resolved {want} (raw {ctx['edge_raw']!r})"
      )
  front = quad["z"] + eff / 2
  if previous_front is not None and front - eff < previous_front - POSITION_TOL:
    problems.append(
      f"{label}: boxes intersect: {quad['id']} reaches back to {front - eff}, behind the previous front {previous_front} (eff {eff} must stay <= half the step)"
    )
  return front


def _slab_loader_problems(ctx, face, ladder, problems):
  """Never-relax (measured incident 2026-11-28): with the flag active and
  an effective thickness above 0 the SlabMesh Loader MUST report Ready(1).
  Error(3) with the module installed - an API bug inside SlabMesh.qml,
  exactly how the invented subset bounds made the box silently never
  exist - is a HARD gate failure; Null(0)/Loading(2) mean the activation
  binding broke. The relaxation is legitimate ONLY when QtQuick3D.Helpers
  is genuinely not installed, and check-layers.py prints a visible SKIP
  line for that case, never a silent OK."""
  label = ctx["label"]
  eff = ladder["eff"]
  if eff <= 1e-12:
    return
  status = int(face.get("slabLoaderStatus", 1))
  if not ctx["helpers"]:
    if status != 0:
      problems.append(
        f"{label}: QtQuick3D.Helpers missing but the slab Loader reports status {status} (it should never have activated)"
      )
    return
  if status != 1:
    problems.append(
      f"{label}: eff thickness {eff} with the flag on but the SlabMesh Loader status is {status}, not Ready (Error=3 means the box never loaded; loader errorString: {face.get('slabLoaderError', '')!r})"
    )


def _face_problems(face, dump, problems):
  """Every clause of one face: context, then the assert groups (each group
  lives in its own helper, same order and short-circuits as the original
  monolith)."""
  ctx = _face_context(face, dump)
  _active_problems(ctx, face, problems)
  _face_material_problems(ctx, face, problems)
  _plate_material_problems(ctx, face, problems)
  _grab_rows_problems(ctx, problems)
  if not ctx["expect_active"]:
    _inactive_face_problems(ctx, face, problems)
    return problems
  _holes_problems(ctx, face, problems)
  shown = _quad_sets_problems(ctx, face, problems)
  if shown is None:
    return problems
  ladder = _depths_problems(ctx, face, dump, shown, problems)
  _stack_shape_problems(ctx, shown, ladder, problems)
  _plate_problems(ctx, face, shown, problems)
  _quad_material_problems(ctx, shown, problems)
  _slab_problems(ctx, shown, ladder, problems)
  _slab_loader_problems(ctx, face, ladder, problems)
  return problems


def validate(dump):
  """All clauses over one scenario dump. Returns a list of problems."""
  problems = []
  faces = dump["faces"]
  if len(faces) != int(dump["faceCount"]):
    problems.append(f"dump: {len(faces)} faces listed, faceCount {dump['faceCount']}")
  # Root mirror of the rotation chain: the live Cube propagation must carry
  # exactly what the resolver + the shared faceOpacity machinery answer (rest
  # 1; turning = clamped key with the 0.1 fade floor; unset raw = the schema
  # default 0.7). The flag-off inactivation itself is pinned per face by
  # _inactive_face_problems (zero quads/layeredIds, intact grabs) plus
  # _face_material_problems (the face follows ONLY faceOpacity).
  expected_layer = expected_layer_opacity(
    bool(dump.get("rotating")), dump.get("layerRotationRaw")
  )
  if not close(dump["layerOpacityLive"], expected_layer):
    problems.append(
      f"dump: Cube.layerOpacity {dump['layerOpacityLive']} != mirrored {expected_layer} (rotating {dump.get('rotating')}, raw {dump.get('layerRotationRaw')})"
    )
  # Virgin-tree parity of the headlight (the ScreenView gate, mirrored by
  # the harness probe): one DirectionalLight with the flag ON, ZERO light
  # nodes with it OFF - the untouched cube keeps its exact scene tree.
  expected_lights = 1 if bool(dump["layering"]) else 0
  if int(dump.get("headlightCount", 0)) != expected_lights:
    problems.append(
      f"dump: headlight count {dump.get('headlightCount')} != {expected_lights} (layering {dump['layering']}: the headlight must exist iff the layers can)"
    )
  if (
    int(dump["currentStubNumber"]) >= 1
    and int(dump["currentFaceIndex"]) != int(dump["currentStubNumber"]) - 1
  ):
    problems.append(
      f"Cube.currentFaceIndex {dump['currentFaceIndex']} != face of desktop {dump['currentStubNumber']}"
    )
  for face in faces:
    _face_problems(face, dump, problems)
  return problems


# ---------------------------------------------------------------------------
# selftest: the oracle must REJECT the classic regressions it exists for.
# Each case takes the good dump and breaks exactly one thing.


def _good_dump():
  dump = {
    "layering": True,
    "faceCount": 3,
    "currentFaceIndex": 0,
    "currentStubNumber": 1,
    "faceWidth": 1000.0,
    "faceHeight": 700.0,
    "gapRaw": 20,
    "lodRaw": 0,
    "plateRaw": 0.25,
    # Slab defaults: no request -> flat quads, bodies hidden.
    "thicknessRaw": 0,
    "edgeRaw": "#141719",
    # Material contract defaults: rest (not rotating) -> the fade chain
    # answers 1, quads Mask, plate Blend; the face follows its own 1.0.
    "rotating": False,
    "helpersInstalled": True,
    "layerRotationRaw": 0.7,
    "faceOpacityLive": 1.0,
    "layerOpacityLive": 1.0,
    # Headlight parity: the good dump has the flag on -> exactly one.
    "headlightCount": 1,
    "faces": [],
  }
  for n in range(1, 4):
    quads = []
    grabs = []
    for i in range(STUB_ROWS):
      win_id = f"stub-{n}-{i}"
      if i in STUB_SHOWN:
        quads.append(
          {
            "id": win_id,
            "order": i,
            "x": 100 + 150 * i + (320 - 40 * i) / 2 - 500,
            "y": 350 - (80 + 120 * i + (200 + 30 * i) / 2),
            # Outward ladder (third amendment: the WHOLE stack floats):
            # rank == order for the stub, so z = (order + 1) * gap +
            # epsilon - the bottom one step off the face, the top window
            # the outermost.
            "z": (i + 1) * 20 + EPSILON,
            "visible": True,
            "showLayer": True,
            "pickable": True,
            "desktopOk": True,
          }
        )
        grabs.append({"id": win_id, "wId": ""})
      else:
        # Dropped rows keep a delegate (the model is unfiltered) but it is
        # hidden and the grab keeps the window flat.
        quads.append(
          {
            "id": win_id,
            "order": i,
            "x": 0,
            "y": 0,
            "z": EPSILON,
            "visible": False,
            "showLayer": False,
            "pickable": True,
            "desktopOk": True,
          }
        )
        grabs.append({"id": win_id, "wId": win_id})
    dump["faces"].append(
      {
        "index": n - 1,
        "desktopNumber": n,
        "active": True,
        "maxRank": 2,
        "fittedGap": 20,
        "layeredIds": [f"stub-{n}-{i}" for i in STUB_SHOWN],
        "quads": quads,
        "grabs": grabs,
        "plateVisible": True,
        "plateZ": -PLATE_EXTRA,
      }
    )
  return _with_layer_fields(dump)


def _with_layer_fields(dump, layer=1.0):
  """Stamp the material-contract + FLAT-slab fields of the live engine
  onto a synthetic dump at the given effective pile opacity (>= MASK_
  THRESHOLD: Mask with the cutoff pinned, below: Blend). The face
  material only ever follows the face knob. Flat stamp: no box, unit
  z-scale 1, the front material NoCulling (the two-sided flat rule)
  while the edge material exists but binds no subset."""
  edge = edge_rgba(dump["edgeRaw"])
  for face in dump["faces"]:
    face["faceAlphaMode"] = "blend"
    face["faceOpacityLive"] = dump["faceOpacityLive"]
    face["faceCutoffLive"] = FACE_CUTOFF
    face["plateAlphaMode"] = "blend"
    face["plateOpacityLive"] = dump["plateRaw"] * layer
    # Flat stamp: no thickness -> the Loader never activates (Null = 0).
    face["slabLoaderStatus"] = 0
    face["slabLoaderError"] = ""
    for quad in face["quads"]:
      quad["alphaMode"] = "mask" if layer >= MASK_THRESHOLD else "blend"
      quad["alphaCutoff"] = FACE_CUTOFF
      quad["materialOpacity"] = layer
      i = int(quad["id"].rsplit("-", 1)[1])
      quad["boxMode"] = "flat"
      quad["boxSubsets"] = 0
      quad["scaleX"] = (320 - 40 * i) / 100
      quad["scaleY"] = (200 + 30 * i) / 100
      quad["scaleZ"] = 1.0
      quad["frontCull"] = "none"
      quad["edgeCull"] = "back"
      quad["frontHasMap"] = True
      quad["edgeAlphaMode"] = "mask" if layer >= MASK_THRESHOLD else "blend"
      quad["edgeOpacity"] = layer
      quad["edgeR"], quad["edgeG"], quad["edgeB"], quad["edgeA"] = edge
      quad["frontLighting"] = UNLIT
      quad["edgeLighting"] = EDGE_LIGHTING
      quad["edgeRoughness"] = EDGE_ROUGHNESS
      quad["edgeMetallic"] = EDGE_METALLIC
    face["faceLighting"] = UNLIT
    face["plateLighting"] = UNLIT
  return dump


def _thick_dump(raw, gap):
  """A good dump with the slab request (px) and the configured step: the
  faces' ladder uses the fitted step of that gap, and every SHOWN layer
  becomes the closed box - z centre shifted back eff/2 so the FRONT
  stays exactly on the ladder, scale z = eff/100, both materials culled,
  the front still textured. (Hidden rows stay flat: they exist only to
  pin the shown/hidden split.)"""
  dump = _good_dump()
  dump["gapRaw"] = gap
  dump["thicknessRaw"] = raw
  fitted = expected_fitted_gap(resolved_gap(gap), 2)
  eff = expected_effective(raw, fitted)
  for face in dump["faces"]:
    face["fittedGap"] = fitted
    # A healthy engine with eff > 0 reports the SlabMesh Loader Ready.
    face["slabLoaderStatus"] = 1 if eff > 0 else 0
    face["slabLoaderError"] = ""
    for quad in face["quads"]:
      if quad["showLayer"]:
        quad["z"] = (quad["order"] + 1) * fitted + EPSILON - eff / 2
        quad["boxMode"] = "box"
        quad["boxSubsets"] = 2
        quad["scaleZ"] = eff / 100
        quad["frontCull"] = "back"
  return dump


def _turning_dump(raw=0.7):
  """A good dump with the cube rotating: the fade chain answers min(1,
  max(0.1, clamp(raw))) (raw None = the schema default 0.7)."""
  dump = _good_dump()
  layer = expected_layer_opacity(True, raw)
  dump["rotating"] = True
  dump["layerRotationRaw"] = raw
  dump["layerOpacityLive"] = layer
  return _with_layer_fields(dump, layer)


def _degraded_dump(raw=300, gap=40):
  """Same knobs as _thick_dump but WITHOUT QtQuick3D.Helpers installed:
  the Loader never activates (status Null), every layer stays flat with
  the plain ladder - the only relaxation the clauses accept."""
  dump = _thick_dump(raw, gap)
  dump["helpersInstalled"] = False
  for face in dump["faces"]:
    face["slabLoaderStatus"] = 0
    face["boxLiveCount"] = 0
    for quad in face["quads"]:
      if quad["showLayer"]:
        quad["z"] = layer_depth_out(quad["order"], face["fittedGap"])
        quad["boxMode"] = "flat"
        quad["boxSubsets"] = 0
        quad["scaleZ"] = 1.0
        quad["frontCull"] = "none"
  return dump


def _flag_off_dump():
  """A good dump with WindowLayering false: zero quads, zero layeredIds,
  every grab id kept intact, plate hidden — and the face material still
  its own (the parity contract with any rotation value in the key)."""
  dump = _good_dump()
  dump["layering"] = False
  # Virgin tree: the headlight Repeater3D has model 0, zero lights.
  dump["headlightCount"] = 0
  for face in dump["faces"]:
    face["active"] = False
    face["quads"] = []
    face["layeredIds"] = []
    face["grabs"] = [{"id": row["id"], "wId": row["id"]} for row in face["grabs"]]
    face["plateVisible"] = False
  return dump


def _material_cases(expects_rejection, failures):
  """The material contract + the two user-confirmed parity clauses (the
  ORDER amendment). Lives apart from selftest() for cognitive complexity
  (Sonar S3776): the geometry regressions are selftest's, the MATERIAL and
  PARITY families are this one's."""
  # --- material contract + the two parity clauses (the ORDER amendment) ---
  expects_rejection(
    "quad Blend at rest",
    lambda d: d["faces"][0]["quads"][0].__setitem__("alphaMode", "blend"),
  )
  expects_rejection(
    # (g2) regression: a layered window at rest must be SOLID (opacity 1)
    # — an opacity off 1 breaks the rest parity with the flat window.
    "rest quad opacity off 1",
    lambda d: d["faces"][0]["quads"][0].__setitem__("materialOpacity", 0.7),
  )
  expects_rejection(
    "quad cutoff drifted while Mask",
    lambda d: d["faces"][0]["quads"][0].__setitem__("alphaCutoff", 0.4),
  )
  expects_rejection(
    "plate lost Blend always",
    lambda d: d["faces"][0].__setitem__("plateAlphaMode", "mask"),
  )
  # (g1): flag off, the key inert at ANY rotation value: the FACE material
  # must not move. A face opacity that stopped matching the face knob is
  # exactly "the face material touched by layerOpacity with the flag off".
  expects_rejection(
    "face touched with flag off",
    lambda d: d["faces"][0].__setitem__("faceOpacityLive", 0.55),
    _flag_off_dump,
  )

  # Positive turning/solid/unset dumps: the fade chain answers 0.7 for the
  # default key (== the face's answer for the same key: parity by
  # construction), 1.0 keeps Mask also WHILE turning, and an unset raw
  # falls back to the schema default.
  turning = _turning_dump()
  if validate(turning):
    failures.append(f"the turning dump (0.7) was rejected: {validate(turning)}")
  expects_rejection(
    "quad Mask while turning at 0.7",
    lambda d: d["faces"][0]["quads"][0].__setitem__("alphaMode", "mask"),
    _turning_dump,
  )
  expects_rejection(
    "plate opacity ignores the fade",
    lambda d: d["faces"][0].__setitem__("plateOpacityLive", 0.25),
    _turning_dump,
  )
  solid = _turning_dump(1.0)
  if validate(solid):
    failures.append(f"the solid-turn dump (key 1.0) was rejected: {validate(solid)}")
  expects_rejection(
    "solid-turn quad dropped the Mask",
    lambda d: d["faces"][0]["quads"][0].__setitem__("alphaMode", "blend"),
    lambda: _turning_dump(1.0),
  )
  unset = _turning_dump(None)
  if validate(unset):
    failures.append(f"the unset-key dump (default 0.7) was rejected: {validate(unset)}")
  expects_rejection(
    "layerOpacity off the mirrored chain",
    lambda d: d.__setitem__("layerOpacityLive", 0.5),
    _turning_dump,
  )


def _slab_cases(expects_rejection, failures):
  """The (h) family: positive thick/fitting dumps and the regressions the
  user's spec asked to kill — request beating the half-step clip, front
  not pinned, a body surviving eff 0, a hard-coded edge alphaMode, and
  two slabs intersecting. Apart from selftest() for S3776."""

  def thick300():
    return _thick_dump(300, 40)

  thick = thick300()
  if validate(thick):
    failures.append(
      f"the thick slab dump (raw 300, gap 40) was rejected: {validate(thick)}"
    )
  fitting = _thick_dump(10, 40)
  if validate(fitting):
    failures.append(
      f"the fitting-request dump (raw 10 < half step) was rejected: {validate(fitting)}"
    )
  coloured = _thick_dump(300, 40)
  coloured["edgeRaw"] = "#ff0000"
  for face in coloured["faces"]:
    for quad in face["quads"]:
      quad["edgeR"], quad["edgeG"], quad["edgeB"], quad["edgeA"] = edge_rgba("#ff0000")
  if validate(coloured):
    failures.append(f"the custom edge-colour dump was rejected: {validate(coloured)}")

  # The request beyond half the step must appear CLIPPED: an engine
  # honouring the raw 300 instead of the effective 20 is the crossing bug.
  expects_rejection(
    "request beating the half-step clip",
    lambda d: d["faces"][0]["quads"][0].__setitem__("scaleZ", 1.0),
    thick300,
  )
  # The FRONT must stay on the ladder even with a body: pushing the front
  # (the delegate itself) back by the half depth is the old assumption
  # that the centre marks the depth.
  expects_rejection(
    "front not pinned to the ladder with thickness on",
    lambda d: d["faces"][0]["quads"][1].__setitem__(
      "z", d["faces"][0]["quads"][1]["z"] - 10
    ),
    thick300,
  )
  # eff 0 keeps the FLAT quad - a boxed layer without effective depth
  # breaks the pixel parity with the quad-only model.
  expects_rejection(
    "boxed layer with zero effective thickness",
    lambda d: (
      d["faces"][0]["quads"][0].__setitem__("boxMode", "box"),
      d["faces"][0]["quads"][0].__setitem__("boxSubsets", 2),
    ),
  )
  # The box must span the EXACT window rect (a fatter box is the bezel
  # bug in geometry form).
  expects_rejection(
    "box larger than the window",
    lambda d: d["faces"][0]["quads"][0].__setitem__("scaleX", 4.0),
    thick300,
  )
  # NoCulling on the closed box = the measured black bezel (the inner
  # side showing through the thumbnail's transparent shadow margins).
  expects_rejection(
    "edge culled NoCulling (the measured bezel)",
    lambda d: d["faces"][0]["quads"][0].__setitem__("edgeCull", "none"),
    thick300,
  )
  # A hard-coded edge alphaMode (never following the threshold):
  expects_rejection(
    "edge material with a fixed alphaMode",
    lambda d: d["faces"][0]["quads"][0].__setitem__("edgeAlphaMode", "opaque"),
    thick300,
  )
  # Intersecting boxes: rank 1 shifted forward enough that its back face
  # crosses rank 0's front (the scale also stops matching the mirror, so
  # this scene dies twice - fine for a regression).
  expects_rejection(
    "slabs intersect",
    lambda d: d["faces"][0]["quads"][1].__setitem__(
      "z", d["faces"][0]["quads"][1]["z"] + 30
    ),
    thick300,
  )
  # The bug this whole clause exists for: the SlabMesh Loader fails to
  # COMPILE (an invented API) while the gate wrongly relaxes as if the
  # module were missing - with the module installed, status 3 is fatal.
  expects_rejection(
    "loader compile error relaxed as missing module (the silent flat bug)",
    lambda d: (
      d["faces"][0].__setitem__("slabLoaderStatus", 3),
      d["faces"][0].__setitem__(
        "slabLoaderError",
        'file:///.../SlabMesh.qml: Cannot assign to non-existent property "boundsMax"',
      ),
    ),
    thick300,
  )
  # The legitimate degradation: QtQuick3D.Helpers genuinely not installed
  # -> flat layers with the plain ladder and status Null, validated as an
  # OK scene (check-layers.py must PRINT a visible SKIP for it).
  degraded = _degraded_dump()
  if validate(degraded):
    failures.append(
      f"the helpers-missing degradation was rejected: {validate(degraded)}"
    )
  # Edge colour off the resolved value:
  expects_rejection(
    "edge colour drift",
    lambda d: d["faces"][0]["quads"][0].__setitem__("edgeR", 0.5),
    thick300,
  )


def _lighting_cases(expects_rejection):
  """The lighting family (measured 2026-11-28: an unlit edge band reads as
  a shadow, not a solid). Edge Fragment + rough matte; front, faces and
  plate keep NoLighting (ADR-026); the camera headlight exists iff the
  flag does (virgin-tree parity)."""
  expects_rejection(
    "edge unlit again (reads as a shadow, not a solid)",
    lambda d: d["faces"][0]["quads"][0].__setitem__("edgeLighting", "none"),
  )
  expects_rejection(
    "textured front re-illuminated (ADR-026 contract broken)",
    lambda d: d["faces"][0]["quads"][0].__setitem__("frontLighting", "fragment"),
  )
  expects_rejection(
    "edge roughness drift (mirror instead of matte)",
    lambda d: d["faces"][0]["quads"][0].__setitem__("edgeRoughness", 0.1),
  )
  expects_rejection(
    "face material touched by the headlight lighting",
    lambda d: d["faces"][0].__setitem__("faceLighting", "fragment"),
  )
  # The headlight gate, both directions.
  expects_rejection(
    "headlight present with the flag off (virgin tree broken)",
    lambda d: d.__setitem__("headlightCount", 1),
    _flag_off_dump,
  )
  expects_rejection(
    "headlight missing with the flag on (edges stay unlit)",
    lambda d: d.__setitem__("headlightCount", 0),
  )


def _unset_cases(expects_rejection, failures):
  """Unset-key family (measured 2026-11-28: a kwinrc holding only
  WindowLayering=true made every other raw arrive as undefined; typed
  properties in the chain coerced it to 0 BEFORE the resolvers, so the
  slab never built, the veil vanished and the ladder collapsed). Every
  resolver must answer the SCHEMA DEFAULT for undefined/None, never the
  range floor; and a full synthetic dump built from nothing but Nones
  must validate as defaults-gap-120."""
  for name, got, want in (
    ("gap", resolved_gap(None), 120),
    ("lod", resolved_lod(None), 1),
    ("plate", resolved_plate(None), 0.25),
    ("thickness", resolved_thickness(None), 24),
    ("rotation", resolved_rotation(None), 0.7),
    ("edge", edge_rgba(None), edge_rgba("#141719")),
  ):
    if got != want:
      failures.append(f"unset {name} resolved to {got}, expected schema default {want}")

  unset = _thick_dump(None, None)
  if validate(unset):
    failures.append(f"the all-undefined dump was rejected: {validate(unset)}")
  # The collapse this exists to catch: raw undefined silently becoming 0
  # (flat slab, epsilon ladder). The engine dump would show it as a
  # boxed-off scene; synthetically, a box-less scene with eff demanded.
  expects_rejection(
    "unset keys collapsed to zero (flat slab, no box)",
    lambda d: (
      d["faces"][0]["quads"][0].__setitem__("boxMode", "flat"),
      d["faces"][0]["quads"][0].__setitem__("scaleZ", 0.0),
    ),
    lambda: _thick_dump(None, None),
  )


def _ladder_cases(failures):
  """The exact-fit (non-fitting), single-window and zero-gap ladders,
  each with their own regression mutation. Lives apart from selftest()
  for cognitive complexity (Sonar S3776); the geometry clause it pins is
  the THIRD amendment: (rank + 1) fitted steps, nobody parked on the
  plane."""
  if validate(_good_dump()):
    failures.append(f"the good synthetic dump did not pass: {validate(_good_dump())}")

  # The exact-fit and zero-gap clauses must fire on their own scenarios:
  # outermost exactly on the cap (maxRank + 1 fitted steps spanning it)
  # and everyone on +epsilon (gap 0).
  tight = _good_dump()
  tight["gapRaw"] = 600
  for face in tight["faces"]:
    face["fittedGap"] = CAP / 3
    for quad in face["quads"]:
      quad["z"] = (quad["order"] + 1) * (CAP / 3) + EPSILON
  if validate(tight):
    failures.append(f"the non-fitting stack (gap 600) was rejected: {validate(tight)}")
  tight["faces"][0]["quads"][2]["z"] = CAP - 10 + EPSILON  # per-layer clamp regression
  if not validate(tight):
    failures.append("per-layer clamp to a plane short of the cap passed the (b) clause")

  # The single-layer ladder (maxRank + 1 == 1): a big raw gap fits the
  # whole cap in its one step, so the lone window floats EXACTLY at
  # cap + epsilon - the anchor-free placement the third amendment asks
  # for even with a single window (the maximized E2/E3 of the harness).
  lone_fitted = expected_fitted_gap(resolved_gap(600), 0)
  if not close(lone_fitted, CAP):
    failures.append(f"single-window stack: fitted {lone_fitted} != cap {CAP}")
  if not close(layer_depth_out(0, lone_fitted), CAP + EPSILON):
    failures.append(
      f"single-window stack: z {layer_depth_out(0, lone_fitted)} != cap + epsilon"
    )

  zero = _good_dump()
  zero["gapRaw"] = 0
  for face in zero["faces"]:
    face["fittedGap"] = 0
    for quad in face["quads"]:
      quad["z"] = EPSILON
  if validate(zero):
    failures.append(f"the gap-0 parity dump was rejected: {validate(zero)}")
  zero["faces"][0]["quads"][1]["z"] = EPSILON + 5
  if not validate(zero):
    failures.append("a gap-0 layer off the +epsilon plane passed the (e) clause")


def selftest():
  failures = []

  def expects_rejection(name, mutate, factory=None):
    dump = (factory or _good_dump)()
    mutate(dump)
    found = validate(dump)
    if not found:
      failures.append(f"{name}: a broken scene passed the oracle")

  expects_rejection(
    "coplanar layers",
    lambda d: d["faces"][0]["quads"][1].__setitem__(
      "z", d["faces"][0]["quads"][2]["z"]
    ),
  )
  expects_rejection(
    "dropped row renders",
    lambda d: d["faces"][0]["quads"][3].__setitem__("visible", True),
  )
  expects_rejection(
    "shown row hidden",
    lambda d: d["faces"][0]["quads"][0].__setitem__("visible", False),
  )
  expects_rejection(
    "over-cap depth",
    lambda d: d["faces"][0]["quads"][0].__setitem__("z", CAP + 60 + EPSILON),
  )
  expects_rejection("hole without a quad", lambda d: d["faces"][0]["quads"].pop(1))
  expects_rejection(
    "grab not released",
    lambda d: d["faces"][0]["grabs"][0].__setitem__(
      "wId", d["faces"][0]["grabs"][0]["id"]
    ),
  )
  expects_rejection(
    "dropped row released", lambda d: d["faces"][0]["grabs"][3].__setitem__("wId", "")
  )
  expects_rejection(
    "lod face instantiates", lambda d: d["faces"][0].__setitem__("active", False)
  )
  expects_rejection(
    "flag-off release",
    lambda d: (d.__setitem__("layering", False), d["faces"][0]["quads"].pop()),
  )
  expects_rejection(
    # The plate in front of the bottom layer (z > +epsilon): it would cover
    # the windows instead of veiling the holes.
    "plate in front of the bottom layer",
    lambda d: d["faces"][0].__setitem__("plateZ", EPSILON + 1),
  )
  expects_rejection(
    # The plate deep behind the face, at the retired inwards position: no
    # longer the veil plane, the interior would show through the holes.
    "plate off the veil plane",
    lambda d: d["faces"][0].__setitem__("plateZ", -(CAP + PLATE_EXTRA)),
  )
  expects_rejection(
    "fitted gap stretched", lambda d: d["faces"][0].__setitem__("fittedGap", CAP / 2)
  )
  expects_rejection(
    "rank map counts dropped rows", lambda d: d["faces"][0].__setitem__("maxRank", 5)
  )
  expects_rejection(
    "wrong current face", lambda d: d.__setitem__("currentFaceIndex", 2)
  )
  # The bug the user saw (2026-11-27): the bottom of the pile parked on
  # the bare epsilon plane - "the bottom window is glued to the desktop
  # all the time". With gap > 0 rank 0 MUST float one fitted step off the
  # face; the exact-ladder clause rejects the old anchored placement.
  expects_rejection(
    "bottom quad anchored on the plane with gap > 0",
    lambda d: d["faces"][0]["quads"][0].__setitem__("z", EPSILON),
  )

  _material_cases(expects_rejection, failures)
  _slab_cases(expects_rejection, failures)
  _lighting_cases(expects_rejection)
  _unset_cases(expects_rejection, failures)

  _ladder_cases(failures)
  return failures


if __name__ == "__main__":
  # The pure oracle is exercisable WITHOUT PySide6: same verdict format as
  # the shared selftest_verdict (check-layers.py --selftest routes here too).
  _failures = selftest()
  print("layers_contract --selftest:", "OK" if not _failures else "FAIL")
  for _failure in _failures:
    print(f" - {_failure}")
  sys.exit(0 if not _failures else 1)
