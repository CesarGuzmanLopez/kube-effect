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
                                 positive, the WHOLE stack floating (bottom
                                 one fitted step off the plane, top window
                                 outermost), no coplanar pair, and the
                                 fitting gap is NEVER stretched to fill
                                 the cap (b).
  overflow gap 600 (raw)        -> (b) fitted step repartido over the
                                 maxRank + 1 steps of the stack: the
                                 outermost quad lands EXACTLY on cap
                                 (150) + epsilon (a single window with a
                                 gap that does not fit: alone at cap +
                                 epsilon; the bottom rises to cap/3 +
                                 epsilon).
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
  thick    request 300 against -> (h) the EFFECTIVE thickness is half
           a step of 40            the step (20) and the layer is ONE
                                   closed THREE-subset box sized to the
                                   VISIBLE FRAME (front textured at
                                   exactly the ladder z - eff/2, four
                                   sides in the lit edge colour, BACK
                                   with the same capture mirrored -
                                   "como la misma pantalla pero al
                                   reves" - all materials
                                   BackFaceCulling: NoCulling was the
                                   measured black bezel, grab-sizing the
                                   wallpaper band, an edge-material back
                                   the dark slab).
  thickfit request 10 (< half  -> eff 10: the request survives when it
           the step)               already fits.
  thickdefault raw UNSET        -> a fresh kwinrc: the resolver answers 24
                                 (measured 2026-11-28: 2 px did not read),
                                 eff min(24, 50/2=25) = 24.
  thickcolour custom #ff0000    -> the edge rgba read live from the
                                   engine matches the resolver.
  defaultsunset EVERY raw knob -> the unset-key regression: real undefined
           undefined (as a    everywhere (a kwinrc with only the flag);
           kwinrc that never  schema defaults must survive the whole
           saved the others)   chain - ladder 120/50, box eff 24, plate
                               0.25, lod 1, rotation 0.7 - never 0.

NEVER-RELAX (measured 2026-11-28, twice the same class of bug): with
the flag on and an effective thickness above 0 the SlabMesh Loader must
report Ready AND every boxed layer must report hasFrameNow - the
delegate must be reading a property that EffectWindow ACTUALLY exposes
("geometry"; "frameGeometry" is scripting-only and reading it produced
the silent grab-fallback of the day, as did the invented subset
boundsMin/boundsMax before). A Loader ERROR with QtQuick3D.Helpers
installed is a HARD FAIL (an invented API once made SlabMesh.qml an
eternal Loader.Error while the gate "relaxed" on a false
missing-module and the box silently never existed). Relaxations apply
ONLY to the two explicit scenes - module absent (visible NOTE SKIP) and
the noframe scenario (no frame name resolves, visible NOTE, box sized to
the grab) - never a silent OK. The dump carries
slabLoaderStatus/slabLoaderError/hasFrameNow per face/quad and
helpersInstalled/stubNoGeometry at root for exactly that.
  (lighting, all thick* + rest): the edge material is Fragment-lit
  (roughness 0.7, metalness 0) while the textured front, the faces and
  the plate stay NoLighting; the camera-anchored headlight Repeater3D is
  mirrored by the harness probe and counted 1 iff WindowLayering - flag
  off = zero light nodes (virgin tree).

For EVERY active face the oracle additionally pins the (d) hole contract
(each layeredIds entry has wId == "" in ITS OWN face grab — the hole
stays, the outward quad floats in front of it — the minimized/dock/
desktopWindow rows keep their id flat), the rank map size (dropped rows
never count), the window-centre positions of the quads, pickable + desktop
re-exposure and the plate position.

--selftest validates the ORACLE (layers_contract.selftest): coplanar
layers, over-cap depths, holes without quads, unreleased grabs, LOD-active
faces instantiating, a plate in front of the bottom layer or off the veil
plane, stretched fitted steps, per-layer clamps short of the cap, the
bottom quad glued to the plane with a positive gap, the slab family
(request beating the half-step clip, front not pinned with thickness on,
a body surviving eff 0, a fixed edge alphaMode, intersecting slabs,
edge-colour drift) and off-+epsilon gap-0 planes must all be rejected;
the fitting, exact-fit, zero-gap, thick and fitting-request good dumps
must pass.

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
  # --- slab body (fourth amendment) ---
  # request 300 against a step of 40: the EFFECTIVE thickness is half the
  # step (20), the front stays exactly on the ladder, the body sits
  # eff/2 + epsilon behind it.
  (
    "thick",
    {
      "desktops": 3,
      "layering": True,
      "gap": 40,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "thickness": 300,
    },
  ),
  # request below half the step: the raw value survives (eff 10).
  (
    "thickfit",
    {
      "desktops": 3,
      "layering": True,
      "gap": 40,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "thickness": 10,
    },
  ),
  # the SCHEMA DEFAULT against the default step: raw UNSET resolves to
  # 24 px (measured 2026-11-28: 2 did not read), and against the fitted
  # step of 50 (gap 120) it survives as eff 24 - a solid-looking box out
  # of a fresh kwinrc.
  (
    "thickdefault",
    {
      "desktops": 3,
      "layering": True,
      "gap": 120,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "thickness": None,
    },
  ),
  # custom edge colour through the raw-string resolver:
  (
    "thickcolour",
    {
      "desktops": 3,
      "layering": True,
      "gap": 40,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "thickness": 300,
      "edge": "#ff0000",
    },
  ),
  # THE SCENARIO THAT CATCHES THE UNSET-KEY BUG (measured 2026-11-28: a
  # kwinrc holding ONLY WindowLayering=true made every other raw arrive
  # as real undefined; int/real properties coerced it to 0 before any
  # resolver ran - flat slabs, invisible veil, collapsed ladder):
  # defaults_unset makes the harness inject undefined for every knob,
  # exactly like effect.configuration does, and the oracle demands the
  # SCHEMA DEFAULTS end to end - ladder of gap 120 (fitted 50 over the 3
  # steps), eff 24 BOX with the lit edge, plate 0.25 visible, lod 1,
  # rotation 0.7.
  (
    "defaultsunset",
    {
      "desktops": 3,
      "layering": True,
      "gap": None,
      "lod": None,
      "plate": None,
      "current": 1,
      "thickness": None,
      "defaults_unset": True,
    },
  ),
  # noframe: the stub windows carry NO geometry property (the EffectWindow
  # accessor simulated as absent). The box stays a box - three subsets,
  # loader Ready - but sized and centred on the GRAB rect: the documented
  # fallback, exercised with a visible NOTE line (never silently, and the
  # thick* scenarios hard-require hasFrameNow true instead).
  (
    "noframe",
    {
      "desktops": 3,
      "layering": True,
      "gap": 40,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "thickness": 300,
      "no_geometry": True,
    },
  ),
  # geometryonly: the scripting name "frameGeometry" is ABSENT and only the
  # EffectWindow-style "geometry" exists (forward-compatible rung of the
  # delegate chain; frameSource must report "geometry").
  (
    "geometryonly",
    {
      "desktops": 3,
      "layering": True,
      "gap": 40,
      "lod": 0,
      "plate": 0.25,
      "current": 1,
      "thickness": 300,
      "geometry_only": True,
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
  # Slab body (fourth amendment): the thickness REQUEST and the raw edge
  # colour string. Default 0 keeps every older scenario flat, so the (h)
  # parity is checked across them all; the thicknessEffective clip and
  # the edgeColor fallback are mirrored from these raw values.
  engine.rootContext().setContextProperty("stubThickness", scenario.get("thickness", 0))
  engine.rootContext().setContextProperty(
    "stubEdgeColor", scenario.get("edge", "#141719")
  )
  # defaultsunset: the harness injects real UNDEFINED for every raw knob
  # (what KWin's effect.configuration returns for keys never saved in
  # kwinrc) - the chain must land on the schema defaults, never on 0.
  engine.rootContext().setContextProperty(
    "stubDefaultsUnset", scenario.get("defaults_unset", False)
  )
  # noframe: the stub windows expose NEITHER frameGeometry (the scripting
  # name - window.h:612 - which is what WindowFilterModel's Window class
  # ACTUALLY has) NOR geometry (the EffectWindow-only name the previous
  # round wrongly trusted) - the delegate chain falls to the grab rect and
  # the oracle accepts the identity crop only here, with a visible NOTE.
  # geometryonly exposes ONLY the secondary "geometry" name to prove the
  # chain's second rung works.
  engine.rootContext().setContextProperty(
    "stubNoFrameProps", scenario.get("no_geometry", False)
  )
  engine.rootContext().setContextProperty(
    "stubFrameOnlyGeometry", scenario.get("geometry_only", False)
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


def _first_frame_source(dump):
  """frameSource of the first shown quad (proof of life printed per
  scenario; apart from main() for S3776)."""
  for face in dump["faces"]:
    for quad in face["quads"]:
      if quad["showLayer"]:
        return str(quad.get("frameSource", "none"))
  return "none"


def main():
  os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
  # Bindings run; nothing is rendered, so the software backend suffices.
  os.environ.setdefault("QT_QUICK_BACKEND", "software")
  qInstallMessageHandler(collect_errors)
  application = QGuiApplication(sys.argv)

  problems: list[str] = []
  kept: list = []
  helpers_absent = False
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
      # Visible NOTE for the exercised fallback (never a silent relax).
      if bool(dump.get("stubNoGeometry")):
        print(
          name + ": NOTE no frame name resolves - the box fell back "
          "to the grab rect (documented degradation)"
        )
      if bool(dump.get("geometryOnly")):
        print(
          name + ": NOTE frameGeometry absent - the chain resolved via "
          "geometry (forward-compatible rung)"
        )
      # A visible SKIP, never a silent OK: the box clauses only relax
      # when QtQuick3D.Helpers is genuinely not installed (a Loader
      # compile error with the module present is a hard failure).
      if not dump.get("helpersInstalled", True):
        helpers_absent = True
        print(name + ": NOTE SKIP of box clauses - QtQuick3D.Helpers is not installed")
      for message in messages:
        problems.append(f"{name} qml: {message.strip()}")
      counts = [len(face["quads"]) for face in dump["faces"]]
      # frame=<source>: proof of life of the chain against the CLASS THE
      # MODEL DELIVERS (scripting Window) - thick*/defaultsunset must show
      # frame=frameGeometry; anything else while the box claims frame data
      # is the frame=0 silent-fallback that fooled three rounds.
      print(
        name
        + ": faces="
        + str(len(counts))
        + " quads="
        + str(counts)
        + " frame="
        + _first_frame_source(dump)
      )
  if problems:
    print("check-layers: FAIL")
    for problem in problems:
      print(f" - {problem}")
    return 1
  # Visible SKIP (never a silent OK): the box clauses relaxed somewhere.
  if helpers_absent:
    print(
      "check-layers: PARTIAL - QtQuick3D.Helpers is NOT installed, the box "
      "clauses were SKIPPED (the layers legitimately degrade to flat)"
    )
  print(
    "check-layers: OK (real Cube/WindowLayers: z strictly increasing with "
    "rank and positive with the WHOLE stack floating (outward, bottom one "
    "fitted step off the plane), outermost exactly on the fixed cap with "
    "the fitted step for every shape including the sheet, gap-0 "
    "+epsilon parity, LOD and flag-off pixel parity, holes exactly where "
    "layeredIds say, dropped rows flat, plate on the -2 veil plane behind "
    "every quad, kwinrc clamps, the Mask/Blend material contract over "
    "layerOpacity (rest Mask + pinned cutoff + opacity 1, turning Blend, "
    "key 1.0 solid Mask, plate Blend x plate-opacity times the fade), the "
    "face-material parity with the flag off at any rotation value, and "
    "the single closed slab box (flat #Rectangle at effective thickness 0 "
    "= parity; three-subset ProceduralMesh with BackFaceCulling when "
    "requested (textured front on the FRAME rect, lit sides, mirrored "
    "shared-texture back); the textured "
    "front exactly on the ladder; consecutive boxes never crossing; "
    "edge Fragment-lit with the rough matte pin while front/faces/plate "
    "stay NoLighting; camera headlight present iff the flag (zero light "
    "nodes for the virgin cube))"
  )
  return 0


if __name__ == "__main__":
  sys.exit(
    dispatch(sys.argv, lambda: selftest_verdict("check-layers", selftest()), main)
  )
