#!/usr/bin/env python3
"""Pure oracle for the window layers (ADR-028, model H), stdlib only.

check-layers.py instantiates the REAL Cube.qml (and through it CubeFace,
WindowLayers, DesktopView and the extended stub WindowFilterModel) in an
offscreen engine, dumps the live quads/grab/plate as JSON and validates
everything here against an INDEPENDENT re-derivation of the ADR-028
formulas — the cap_contract.py pattern for the caps. The oracle never
trusts the engine for the math: expected depths, ranks, fitted steps,
holes and plate positions are recomputed from the dump's own geometry
(faceDistance / isSheet) plus the mirrored kwinrc clamps.

Clause families (the five innegociable asserts of the ADR-028 "Puertas"):
  (a) strict monotony: no two layers of a face coplanar, exact order by rank;
  (b) budget: every depth <= maxLayerDepth and a stack that does not fit
      lands EXACTLY on maxLayerDepth (one fitted step for all, no per-layer
      clamp, no stretch when the configured gap already fits);
  (c) LOD off and flag off: zero quads instantiated and the grab keeps
      every internalId (pixel parity with the cube of before);
  (d) every id in layeredIds has wId == "" in its face grab, and every id
      NOT layered (minimized/dock/desktopWindow) keeps its internalId;
  (e) gap 0: every layer of a face shares z == -epsilon.

Stub window layout (mirrored from qml_check_harness.STUB_MODULE; keep the
two in sync when the stub changes): desktop n has rows i = 0..5 with
internalId "stub-<n>-<i>", stackingOrder i, x = 100+150i, y = 80+120i,
width = 320-40i, height = 200+30i; i=3 minimized, i=4 dock, i=5
desktopWindow. The ordinary rows 0..2 must win quads; 3..5 must never.
"""

import sys

# The layerGeometry.js constants (a drift fails the gate, the point of
# mirroring them here).
CAP = 150.0
EPSILON = 0.01
PLATE_EXTRA = 2
GAP_MIN, GAP_MAX, GAP_DEFAULT = 0, 600, 120
LOD_MIN, LOD_MAX, LOD_DEFAULT = 0, 8, 1
PLATE_MIN, PLATE_MAX, PLATE_DEFAULT = 0.0, 1.0, 0.25

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


def expected_max_depth(is_sheet, face_distance):
  if is_sheet:
    return CAP
  try:
    distance = float(face_distance)
  except (TypeError, ValueError):
    return CAP
  return max(0.0, min(distance * 0.5, CAP))


def expected_fitted_gap(gap, max_depth, max_rank):
  steps = max(1, int(max_rank))
  return min(gap, max_depth / steps)


def lod_distance(index, current, face_count):
  raw = abs(int(index) - int(current))
  return min(raw, int(face_count) - raw)


def _face_context(face, dump):
  """The mirrored per-face values every clause group needs (no checks here)."""
  layering = bool(dump["layering"])
  lod = resolved_lod(dump["lodRaw"])
  gap = resolved_gap(dump["gapRaw"])
  plate = resolved_plate(dump["plateRaw"])
  max_depth = expected_max_depth(dump["isSheet"], dump["faceDistance"])
  current = int(dump["currentFaceIndex"])
  return {
    "label": f"face {face['index']} (desktop {face['desktopNumber']})",
    "layering": layering,
    "lod": lod,
    "gap": gap,
    "plate": plate,
    "max_depth": max_depth,
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


def _budget_and_active_problems(ctx, face, problems):
  """Cube mirrors (the budget formula AND the LOD decision): the gate does
  not only check depths, a diverging Cube/WindowLayers budget or flag would
  pass math computed against the mirror while the scene used another one."""
  label = ctx["label"]
  if not close(face["maxDepthFromCube"], ctx["max_depth"]):
    problems.append(
      f"{label}: Cube.layerMaxDepth {face['maxDepthFromCube']} != mirrored {ctx['max_depth']}"
    )
  if bool(face["active"]) is not ctx["expect_active"]:
    problems.append(
      f"{label}: active {face['active']}, expected {ctx['expect_active']} (flag {ctx['layering']}, lod {ctx['lod']}, current {ctx['current']})"
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
  """maxRank/fittedGap mirrors plus every quad's z on the fitted ladder,
  its budget bound and its window-centre coincidence. Returns the depth
  map the stack-shape clause needs."""
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
  max_depth = ctx["max_depth"]
  fitted = expected_fitted_gap(gap, max_depth, max_rank)
  if not close(face["fittedGap"], fitted):
    problems.append(f"{label}: fittedGap {face['fittedGap']} != mirrored {fitted}")

  depths = {}
  for quad in shown:
    rank = sum(1 for other in orders if other < quad["order"])
    depths[quad["id"]] = (max_rank - rank) * fitted
    _quad_depth_problems(label, quad, rank, fitted, max_rank, max_depth, dump, problems)
  return {"depths": depths, "fitted": fitted, "max_rank": max_rank, "orders": orders}


def _quad_depth_problems(
  label, quad, rank, fitted, max_rank, max_depth, dump, problems
):
  """One quad on the ladder: exact z, never past the budget, strictly
  behind the face plane, centred over its own window (the hole and the
  quad coincide; local px, Y flips)."""
  depth = (max_rank - rank) * fitted
  expected_z = -(depth + EPSILON)
  if not close(quad["z"], expected_z, POSITION_TOL):
    problems.append(
      f"{label}: quad {quad['id']} z {quad['z']} != {expected_z} (rank {rank}, fitted {fitted})"
    )
  # (b) every layer within the budget (never past the cap).
  if depth > max_depth + 1e-9:
    problems.append(
      f"{label}: quad {quad['id']} depth {depth} exceeds the budget {max_depth}"
    )
  if quad["z"] > -EPSILON + 1e-9:
    problems.append(
      f"{label}: quad {quad['id']} is not strictly behind the face plane (z {quad['z']})"
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
  """(a) strict rank monotony + (b) the exact-budget landing of a
  non-fitting stack (and no stretch for a fitting one) + (e) the gap-0
  epsilon parity."""
  label = ctx["label"]
  gap = ctx["gap"]
  max_depth = ctx["max_depth"]
  fitted = ladder["fitted"]
  max_rank = ladder["max_rank"]
  if fitted <= 0:
    # (e) gap 0: every layer shares the epsilon plane (flat parity).
    for quad in shown:
      if not close(quad["z"], -EPSILON):
        problems.append(
          f"{label}: zero gap put {quad['id']} at z {quad['z']}, expected {-EPSILON}"
        )
    return
  # (a) strict monotony by rank: the front-most window (max order) is the
  # shallowest quad and no two layers ever share a plane.
  zs = sorted((q["order"], q["z"]) for q in shown)
  for k in range(1, len(zs)):
    if zs[k][1] <= zs[k - 1][1] + 1e-9:
      problems.append(f"{label}: layers not strictly ordered by rank: {zs}")
  # A stack that does not fit MUST land exactly on the budget (repartido,
  # no per-layer clamp): the deepest quad (largest depth) reaches max_depth.
  if gap * max_rank > max_depth + 1e-9:
    deepest = max(ladder["depths"].values())
    if not close(deepest, max_depth, POSITION_TOL):
      problems.append(
        f"{label}: non-fitting stack deepest depth {deepest} != budget {max_depth}"
      )
  # A gap that fits is never stretched to fill the budget.
  if gap * max_rank <= max_depth and not close(fitted, gap):
    problems.append(f"{label}: fitting gap {gap} was stretched to {fitted}")


def _plate_problems(ctx, face, problems):
  """The plate sits behind the DEEPEST layer, never in front of it, and
  only shows while its alpha is on (multiplied by the face opacity
  downstream)."""
  label = ctx["label"]
  max_depth = ctx["max_depth"]
  if not close(face["plateZ"], -(max_depth + PLATE_EXTRA), POSITION_TOL):
    problems.append(
      f"{label}: plate z {face['plateZ']} != -(maxLayerDepth + {PLATE_EXTRA}) = {-(max_depth + PLATE_EXTRA)}"
    )
  if bool(face["plateVisible"]) is not (ctx["plate"] > 0.001):
    problems.append(
      f"{label}: plate visible {face['plateVisible']} with plateOpacity {ctx['plate']}"
    )


def _face_problems(face, dump, problems):
  """Every clause of one face: context, then the assert groups (each group
  lives in its own helper, same order and short-circuits as the original
  monolith)."""
  ctx = _face_context(face, dump)
  _budget_and_active_problems(ctx, face, problems)
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
  _plate_problems(ctx, face, problems)
  return problems


def validate(dump):
  """All clauses over one scenario dump. Returns a list of problems."""
  problems = []
  faces = dump["faces"]
  if len(faces) != int(dump["faceCount"]):
    problems.append(f"dump: {len(faces)} faces listed, faceCount {dump['faceCount']}")
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
    "isSheet": False,
    "faceDistance": 966.0,  # budget clamps to the cap either way
    "faceWidth": 1000.0,
    "faceHeight": 700.0,
    "gapRaw": 20,
    "lodRaw": 0,
    "plateRaw": 0.25,
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
            "z": -((2 - i) * 20 + EPSILON),
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
            "z": -EPSILON,
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
        "maxDepthFromCube": CAP,
        "maxRank": 2,
        "fittedGap": 20,
        "layeredIds": [f"stub-{n}-{i}" for i in STUB_SHOWN],
        "quads": quads,
        "grabs": grabs,
        "plateVisible": True,
        "plateZ": -(CAP + PLATE_EXTRA),
      }
    )
  return dump


def selftest():
  failures = []

  def expects_rejection(name, mutate):
    dump = _good_dump()
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
    "over-budget depth",
    lambda d: d["faces"][0]["quads"][0].__setitem__("z", -(CAP + 60 + EPSILON)),
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
    "plate in front", lambda d: d["faces"][0].__setitem__("plateZ", -(CAP - 10))
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

  if validate(_good_dump()):
    failures.append(f"the good synthetic dump did not pass: {validate(_good_dump())}")

  # The exact-fit and zero-gap clauses must fire on their own scenarios:
  # deepest exactly on the budget (fitted) and everyone on -epsilon (gap 0).
  tight = _good_dump()
  tight["gapRaw"] = 600
  for face in tight["faces"]:
    face["fittedGap"] = CAP / 2
    for quad in face["quads"]:
      quad["z"] = -((2 - quad["order"]) * (CAP / 2) + EPSILON)
  if validate(tight):
    failures.append(f"the non-fitting stack (gap 600) was rejected: {validate(tight)}")
  tight["faces"][0]["quads"][0]["z"] = -(140 + EPSILON)  # per-layer clamp regression
  if not validate(tight):
    failures.append("per-layer clamp to a plane below the budget passed the (b) clause")

  zero = _good_dump()
  zero["gapRaw"] = 0
  for face in zero["faces"]:
    face["fittedGap"] = 0
    for quad in face["quads"]:
      quad["z"] = -EPSILON
  if validate(zero):
    failures.append(f"the gap-0 parity dump was rejected: {validate(zero)}")
  zero["faces"][0]["quads"][1]["z"] = -EPSILON - 5
  if not validate(zero):
    failures.append("a gap-0 layer off the epsilon plane passed the (e) clause")
  return failures


if __name__ == "__main__":
  # The pure oracle is exercisable WITHOUT PySide6: same verdict format as
  # the shared selftest_verdict (check-layers.py --selftest routes here too).
  _failures = selftest()
  print("layers_contract --selftest:", "OK" if not _failures else "FAIL")
  for _failure in _failures:
    print(f" - {_failure}")
  sys.exit(0 if not _failures else 1)
