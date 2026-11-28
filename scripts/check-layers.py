#!/usr/bin/env python3
"""Offscreen gate for the window layers (ADR-028, model H as amended
2026-11-27: the stack travels OUTWARDS, +z along the face normal).

Instantiates the REAL Cube.qml against the shared stub org.kde.kwin module
(qml_check_harness.STUB_MODULE — one copy, the same VirtualDesktopModel/
WindowFilterModel the wiring gate uses) inside an offscreen QML engine —
and through Cube the live CubeFace node, the WindowLayers quads and plate,
the WindowFilterModel rows and the face grab (DesktopView thumbnails).
Nothing is rendered: the object tree is dumped as JSON and validated by
the pure oracle in layers_contract.py against an independent
re-derivation of the amended ADR-028 formulas. The scenario families cover
the ADR-028 "Puertas" (amended):

  off      flag false, 3 faces  -> (c) zero quads everywhere, every grab
                                 keeps its internalId, plate hidden:
                                 pixel parity with the cube of before.
  fits     gap 20, lod 0        -> (a) z strictly INCREASING with rank and
                                 positive (top window outermost), no
                                 coplanar pair, and the fitting gap is
                                 NEVER stretched to fill the cap (b).
  overflow gap 600 (raw)        -> (b) fitted step repartido: the outermost
                                 quad lands EXACTLY on cap (150) + epsilon.
  gap0     gap 0                -> (e) every layer shares z = +epsilon.
  lod      5 faces, lod 1       -> (c) faces at index distance 2 from the
                                 current desktop instantiate NO quads and
                                 the grab keeps every id there.
  sheet    2 faces (flat sheet) -> the FIXED cap applies to the sheet too
                                 (amendment rule: no per-shape budget left;
                                 the old sheet branch died with the inward
                                 stack) — same exact-landing check as the
                                 polygon overflow scenario.
  plate0   plate 0              -> the plate hides, its z still exactly
                                 -2: the veil plane just behind the face
                                 (clause (f): it must stay behind EVERY
                                 quad so the holes never show the interior).
  clamp    gap -50, lod 13,     -> the resolvedors: gap clamps to 0 (all
           plate 3.0               layers at +epsilon), lod to 8 (all
                                   faces active), plate to 1 (visible).
  turning  rotating, key 0.7    -> (g) the pile fades to 0.7 == what the
                                   face machinery answers for the same
                                   key (parity by construction): quads
                                   Blend with material opacity 0.7, plate
                                   0.25 x 0.7.
  solidturn key 1.0 rotating    -> (g) solid windows WHILE turning: the
                                   Mask (cutoff pinned 0.5) and depth
                                   order stay on — the outermost rank
                                   wins every overlap by geometry.
  rotclamp raw -5 rotating      -> resolver 0 + the shared 0.1 fade floor
                                   of Constants.faceOpacity.
  rotunset raw unset rotating   -> the SCHEMA DEFAULT 0.7 answers (never
                                   the range floor, ADR-022).
  offrot   flag OFF with the    -> (g1) the key is inert at ANY value:
           key 0.2, faces 0.5     zero quads, zero layeredIds, grabs
  offrot1  (and the same with   intact, and the live FACE materials
  offrot07  1.0 and 0.7)        follow ONLY faceOpacity — with layers
                                   off the windows are pixels of the
                                   grab and share the desktop's
                                   transparency.

For EVERY active face the oracle additionally pins the (d) hole contract
(each layeredIds entry has wId == "" in ITS OWN face grab — the hole
stays, the outward quad floats in front of it — the minimized/dock/
desktopWindow rows keep their id flat), the rank map size (dropped rows
never count), the window-centre positions of the quads, pickable + desktop
re-exposure and the plate position.

--selftest validates the ORACLE (layers_contract.selftest): coplanar
layers, over-cap depths, holes without quads, unreleased grabs, LOD-active
faces instantiating, a plate in front of the bottom layer or off the veil
plane, stretched fitted steps, per-layer clamps short of the cap and
off-+epsilon gap-0 planes must all be rejected; the fitting, exact-fit and
zero-gap good dumps must pass.

Skipped (exit 0) when PySide6 is missing (the shared skip contract).
"""

import json
import os
import sys
import tempfile

try:
  from PySide6.QtCore import QUrl, qInstallMessageHandler
  from PySide6.QtGui import QGuiApplication
  from PySide6.QtQml import QQmlComponent, QQmlEngine
except ImportError:  # pragma: no cover - optional dependency
  print("check-layers: skipped (PySide6 is not installed)")
  sys.exit(0)

from layers_contract import selftest, validate
from qml_check_harness import (
  QML_ERROR_SIGNATURES,
  ROOT,
  dispatch,
  selftest_verdict,
  write_stub_module,
)

messages: list[str] = []


def collect_errors(_mode, _context, message):
  if any(signature in message for signature in QML_ERROR_SIGNATURES):
    messages.append(message)


# (name, desktops, layering, raw gap, raw lod, raw plate, current number).
# The knobs travel to QML UNRESOLVED (context properties); Cube clamps
# them through layerGeometry.js and the oracle mirrors the clamps.
_SCENARIOS = [
  (
    "off",
    {
      "desktops": 3,
      "layering": False,
      "gap": 120,
      "lod": 1,
      "plate": 0.25,
      "current": 1,
    },
  ),
  (
    "fits",
    {"desktops": 3, "layering": True, "gap": 20, "lod": 0, "plate": 0.25, "current": 1},
  ),
  (
    "overflow",
    {
      "desktops": 3,
      "layering": True,
      "gap": 600,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
    },
  ),
  (
    "gap0",
    {"desktops": 3, "layering": True, "gap": 0, "lod": 0, "plate": 0.25, "current": 1},
  ),
  (
    "lod",
    {
      "desktops": 5,
      "layering": True,
      "gap": 120,
      "lod": 1,
      "plate": 0.25,
      "current": 1,
    },
  ),
  (
    "sheet",
    {
      "desktops": 2,
      "layering": True,
      "gap": 600,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
    },
  ),
  (
    "plate0",
    {"desktops": 3, "layering": True, "gap": 120, "lod": 0, "plate": 0.0, "current": 1},
  ),
  (
    "clamp",
    {
      "desktops": 3,
      "layering": True,
      "gap": -50,
      "lod": 13,
      "plate": 3.0,
      "current": 1,
    },
  ),
  # --- material contract + the fade key (ADR-028 order amendment) ---
  # rotating with the default key: the pile fades to 0.7 (== what the face
  # answers for FaceRotationOpacity 0.7) and the quads drop to Blend.
  (
    "turning",
    {
      "desktops": 3,
      "layering": True,
      "gap": 20,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "rotation": 0.7,
      "rotating": True,
    },
  ),
  # key 1.0 while turning: solid windows, the depth-ordered Mask stays on.
  (
    "solidturn",
    {
      "desktops": 3,
      "layering": True,
      "gap": 20,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "rotation": 1.0,
      "rotating": True,
    },
  ),
  # raw -5 while turning: resolver clamps to 0, then the shared face fade
  # floor lifts the value to 0.1 (the same rule the faces obey).
  (
    "rotclamp",
    {
      "desktops": 3,
      "layering": True,
      "gap": 20,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "rotation": -5,
      "rotating": True,
    },
  ),
  # key never saved while turning: the SCHEMA DEFAULT 0.7 answers (never
  # the range floor, the ADR-022 rule).
  (
    "rotunset",
    {
      "desktops": 3,
      "layering": True,
      "gap": 20,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "rotation": None,
      "rotating": True,
    },
  ),
  # (g1) flag OFF with the key mid-fade AND the faces half transparent:
  # zero quads everywhere, grabs intact, the face materials follow ONLY
  # faceOpacity — the rotation key is provably inert without layers.
  (
    "offrot",
    {
      "desktops": 3,
      "layering": False,
      "gap": 120,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "rotation": 0.2,
      "rotating": True,
      "faceOp": 0.5,
    },
  ),
  # (g1) again at the other two test values of the key (1.0 and the
  # default): identical expectations, still inert with the flag off.
  (
    "offrot1",
    {
      "desktops": 3,
      "layering": False,
      "gap": 120,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "rotation": 1.0,
      "rotating": True,
      "faceOp": 0.5,
    },
  ),
  (
    "offrot07",
    {
      "desktops": 3,
      "layering": False,
      "gap": 120,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "rotation": 0.7,
      "rotating": True,
      "faceOp": 0.5,
    },
  ),
]


def _instantiate(application, import_root, scenario):
  """One engine per scenario: the stub count and the knobs are CONTEXT
  properties fixed at load time (the check-cylinder-wiring pattern).

  Returns (harness, dump, keep): dump is None on load/create failure and
  keep then carries the problem strings; otherwise keep is the
  (engine, component) pair the caller must keep alive next to the
  harness (PySide would destroy the object tree otherwise)."""
  engine = QQmlEngine()
  engine.addImportPath(str(import_root))
  engine.rootContext().setContextProperty("stubDesktopCount", scenario["desktops"])
  engine.rootContext().setContextProperty("stubLayering", scenario["layering"])
  engine.rootContext().setContextProperty("stubGap", scenario["gap"])
  engine.rootContext().setContextProperty("stubLod", scenario["lod"])
  engine.rootContext().setContextProperty("stubPlate", scenario["plate"])
  # The rotation-opacity family (the ORDER amendment): raw key, simulated
  # cubeMoving and the FACE opacity knob for the parity clause. Absent
  # keys arrive as None -> the QML typeof guard answers null/False and
  # the runtime fallbacks (schema default 0.7, rest) are exercised.
  engine.rootContext().setContextProperty("stubLayerRotation", scenario.get("rotation"))
  engine.rootContext().setContextProperty(
    "stubRotating", scenario.get("rotating", False)
  )
  engine.rootContext().setContextProperty(
    "stubFaceOpacity", scenario.get("faceOp", 1.0)
  )
  engine.rootContext().setContextProperty("stubCurrentNumber", scenario["current"])
  component = QQmlComponent(engine)
  component.loadUrl(QUrl.fromLocalFile(str(ROOT / "scripts/check-layers.qml")))
  if component.isError():
    return None, None, [f"load: {error.toString()}" for error in component.errors()]
  harness = component.create()
  if harness is None:
    return None, None, [f"create: {component.errorString()}"]
  application.processEvents()
  dump = json.loads(str(harness.property("dumpJson")))
  return harness, dump, (engine, component)


def main():
  os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
  # Bindings run; nothing is rendered, so the software backend suffices.
  os.environ.setdefault("QT_QUICK_BACKEND", "software")
  qInstallMessageHandler(collect_errors)
  application = QGuiApplication(sys.argv)

  problems: list[str] = []
  kept: list = []
  with tempfile.TemporaryDirectory(prefix="kube-stub-") as temporary:
    import_root = write_stub_module(temporary)
    for name, scenario in _SCENARIOS:
      messages.clear()
      _harness, dump, keep = _instantiate(application, import_root, scenario)
      if dump is None:
        problems.extend(f"{name}: {problem}" for problem in keep)
        continue
      kept.append(keep)
      problems.extend(f"{name}: {problem}" for problem in validate(dump))
      for message in messages:
        problems.append(f"{name} qml: {message.strip()}")
      counts = [len(face["quads"]) for face in dump["faces"]]
      print(name + ": faces=" + str(len(counts)) + " quads=" + str(counts))
  if problems:
    print("check-layers: FAIL")
    for problem in problems:
      print(f" - {problem}")
    return 1
  print(
    "check-layers: OK (real Cube/WindowLayers: z strictly increasing with "
    "rank and positive (outward stack), outermost exactly on the fixed cap "
    "with the fitted step for every shape including the sheet, gap-0 "
    "+epsilon parity, LOD and flag-off pixel parity, holes exactly where "
    "layeredIds say, dropped rows flat, plate on the -2 veil plane behind "
    "every quad, kwinrc clamps, the Mask/Blend material contract over "
    "layerOpacity (rest Mask + pinned cutoff + opacity 1, turning Blend, "
    "key 1.0 solid Mask, plate Blend x plate-opacity times the fade) and "
    "the face-material parity with the flag off at any rotation value)"
  )
  return 0


if __name__ == "__main__":
  sys.exit(
    dispatch(sys.argv, lambda: selftest_verdict("check-layers", selftest()), main)
  )
