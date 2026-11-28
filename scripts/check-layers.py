#!/usr/bin/env python3
"""Offscreen gate for the window layers (ADR-028, model H).

Instantiates the REAL Cube.qml against the shared stub org.kde.kwin module
(qml_check_harness.STUB_MODULE — one copy, the same VirtualDesktopModel/
WindowFilterModel the wiring gate uses) inside an offscreen QML engine —
and through Cube the live CubeFace node, the WindowLayers quads and plate,
the WindowFilterModel rows and the face grab (DesktopView thumbnails).
Nothing is rendered: the object tree is dumped as JSON and validated by
the pure oracle in layers_contract.py against an independent re-derivation
of the ADR-028 formulas. The scenario families cover the ADR-028 "Puertas":

  off      flag false, 3 faces  -> (c) zero quads everywhere, every grab
                                 keeps its internalId, plate hidden:
                                 pixel parity with the cube of before.
  fits     gap 20, lod 0        -> (a) strict rank monotony, no coplanar
                                 pair, and the fitting gap is NEVER
                                 stretched to fill the budget (b).
  overflow gap 600 (raw)        -> (b) fitted step repartido: the deepest
                                 quad lands EXACTLY on maxLayerDepth (150).
  gap0     gap 0                -> (e) every layer shares z = -epsilon.
  lod      5 faces, lod 1       -> (c) faces at index distance 2 from the
                                 current desktop instantiate NO quads and
                                 the grab keeps every id there.
  sheet    2 faces (flat sheet) -> the sheet budget is the CAP directly
                                 (ADR-028 rule 2: faceDistance here is the
                                 few-px sheetGap; the solid formula would
                                 crush the stack to ~1 px).
  plate0   plate 0              -> the plate hides, its z still exactly
                                 maxLayerDepth + 2 behind.
  clamp    gap -50, lod 13,     -> the resolvedors: gap clamps to 0 (all
           plate 3.0               layers at -epsilon), lod to 8 (all
                                   faces active), plate to 1 (visible).

For EVERY active face the oracle additionally pins the (d) hole contract
(each layeredIds entry has wId == "" in ITS OWN face grab; the minimized/
dock/desktopWindow rows keep their id flat — a hole without a quad is a
hole in the shell), the rank map size (dropped rows never count), the
window-centre positions of the quads, pickable + desktop re-exposure and
the plate position.

--selftest validates the ORACLE (layers_contract.selftest): coplanar
layers, over-budget depths, holes without quads, unreleased grabs,
LOD-active faces instantiating, plate in front, stretched fitted steps,
per-layer clamps and off-epsilon gap-0 planes must all be rejected; the
fitting, exact-fit and zero-gap good dumps must pass.

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
      print(
        name
        + ": faces="
        + str(len(counts))
        + " sheet="
        + str(int(dump["isSheet"]))
        + " quads="
        + str(counts)
      )
  if problems:
    print("check-layers: FAIL")
    for problem in problems:
      print(f" - {problem}")
    return 1
  print(
    "check-layers: OK (real Cube/WindowLayers: strict rank monotony, exact "
    "budget landing with the fitted step, cap-direct sheet, gap-0 epsilon "
    "parity, LOD and flag-off pixel parity, holes exactly where layeredIds "
    "say, dropped rows flat, plate behind the deepest layer, kwinrc clamps)"
  )
  return 0


if __name__ == "__main__":
  sys.exit(
    dispatch(sys.argv, lambda: selftest_verdict("check-layers", selftest()), main)
  )
