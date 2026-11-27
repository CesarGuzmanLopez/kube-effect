#!/usr/bin/env python3
"""Pixel gate for the ADR-027 caps: paint order, silhouette, and the mirror.

The user measured (nested KWin, 1600x900, shape=poly n=3, separation 10,
both caps, Color content, opacity 80): the cap paints OVER nearer faces
("a angulos atraviesa el triangulo"), does not seal the gap, and the whole
thing "looks 180 flipped". The mesh is already proven correct (check-cap.py
/ cap_contract.py), so this gate renders the REAL Cube.qml with its REAL
cap models and decides with pixels:

  a) crossing : pixels whose caps-OFF reference shows a face the geometric
     oracle confirms as FRONT must never show the cap colour once the caps
     are on. Cap.qml historically kept alphaMode Blend always (the ADR-026
     regime split did not reach the caps): the transparent pass then sorts
     by NODE CENTROID only (0, +/-H/2), and a cap centroid closer than a
     face's paints over faces that are physically in front of the cap
     surface. That is the hypothesis this counter measures;
  b) silhouette : every cap-coloured pixel must lie on the cap's own
     projected polygon (outside counter), and a pixel the cap should own
     over the background must actually show the cap (gapopen counter = the
     user's "no tapa el hueco"); a pixel the cap should own over a face,
     painted with the face instead, is caplost;
  c) mirror : variants isolate CapTop / CapBottom / both (the union must
     match), and the bottom cap WITHOUT Cube.qml's 180 X node rotation
     against the real rotated one (silhouettes must match: a planar
     regular ring is symmetric under the mirror — if they differ, the 180
     analysis is wrong and the pixels say so with numbers);
  d) opacity : the sweep runs at CapOpacity 80 (Blend, the user setting)
     and 100 (the Mask regime of the fix), printing both rows; this is
     what separates "wrong pass by alpha" from "no depth write";
  e) content mirror (mission item 3, measured not asserted): the
     asymmetric PNG (cap-base, magenta quadrant, cyan stripe) is rendered
     alone on the top and the bottom cap; the marker centroids are printed
     row by row — a mirrored TEXTURE on the bottom cap is the visible half
     of the "180 volteado" complaint even when the silhouette is fine;
  f) arrow marker (ADR-027 amendment 2, the default CapContent): same
     centroid table for CapArrow.qml (magenta quadrant + cyan arrow). If
     the marker does not paint on a visible cap the gate FAILS (Shapes
     degradation must stay a warning, never a silent blank).

The cap colour here is ORANGE (#ff8000), not the user's blue: the shared
stub paints desktop 3 with PURE BLUE, so a blue cap and that face's inner
wall are pixel-identical (measured in the first pilot: the outside counter
lit up 218 times for the far face, not the cap). The material regime under
test is colour-agnostic. Magenta and cyan stay free for the content
markers.

The geometric oracle (front surface per sampled pixel) is pure Python and
--selftest drives it with SYNTHETIC grabs built FROM the oracle: a
truanted scene where the cap bleeds over the front face, one that paints
outside its ring, one that leaves the hole open, one where the face behind
wins, and a clean scene. A validator that cannot light up on those is
worthless.

Skipped (exit 0) without PySide6, without a display, or on the
offscreen/minimal platforms (QtQuick3D does not render there). The boot is
the shared qml_check_harness.view_boot (warm-up without a Python handler,
handler, QQuickView) — not a copy of check-cylinder-overlap's.
"""

import importlib.util
import json
import math
import os
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=DeprecationWarning)

from cap_contract import cap_ring
from qml_check_harness import (
    QML_ERROR_SIGNATURES,
    ROOT,
    pump,
    require_pyside,
    selftest_verdict,
    view_boot,
)

require_pyside("check-cap-overlap")

_spec = importlib.util.spec_from_file_location(
    "check_video_dome_for_stubs", ROOT / "scripts/check-video-dome.py"
)
_dome = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_dome)

# -- Harness geometry (mirrors check-cap-overlap.qml = the user capture).
FACE_W = 1600.0
FACE_H = 900.0
HALF_W = FACE_W / 2
HALF_H = FACE_H / 2
N = 3
TICK = 2 * math.pi / N
GAP = 10.0
APOTHEM = HALF_W / math.tan(math.pi / N) + GAP
CAM_Z = APOTHEM + 0.5 * FACE_H / math.tan(0.5 * 60 * math.pi / 180) + 900
VIEW_W = 800
VIEW_H = 450
FOV_TAN = math.tan(0.5 * 60 * math.pi / 180)
ASPECT = VIEW_W / VIEW_H

# Cap ring straight from the shared contract (no second derivation).
CAP_ALPHAS, CAP_RHO, CAP_REGIME = cap_ring(APOTHEM, N, FACE_W)
CAP_POLY = [(CAP_RHO * math.sin(a), CAP_RHO * math.cos(a)) for a in CAP_ALPHAS]

FACE_CLASSES = ("R", "G", "B")  # stub desktops 1/2/3, Repeater order.
CAP_RGB = (255, 128, 0)  # orange, see the module docstring.

PITCHES = (0.0, 15.0, 30.0, 45.0, 60.0)
YAWS = (0.0, 60.0, 120.0, 154.0, 180.0, 240.0, 300.0)
STEP = 8

FACE_CLASS_RGB = {
    "R": (255, 0, 0),
    "G": (0, 255, 0),
    "B": (0, 0, 255),
    "O": CAP_RGB,
    "M": (255, 0, 255),
    "C": (0, 255, 255),
    "K": (0, 0, 0),
}

VARIANTS = {
    # name: (harness variant int, caps in the oracle, capOpacity)
    "v1@80": (1, ("top", "bottom"), 80),
    "v1@100": (1, ("top", "bottom"), 100),
    "v2top": (2, ("top",), 80),
    "v3bot": (3, ("bottom",), 80),
    "v4loose": (4, ("bottom",), 80),
}


def classify(rgb):
    """Dominant class of a pixel. The cap is orange #ff8000; its 80 % blend
    over every other class stays in the O box (r > 150, 90 < g < 210,
    b < 90): over red (255, 102, 0), over green (204, 153, 0), over blue
    (204, 102, 51), over black (204, 102, 0). No face, marker or clear
    colour reaches it: red has g < 70, green r < 70, blue r < 70, magenta
    b > 195, cyan b > 150 and r < 110."""
    r, g, b = rgb
    if g > 150 and b > 150 and r < 110:
        return "C"
    if r > 195 and b > 195 and g < 70:
        return "M"
    if b > 195 and r < 70 and g < 70:
        return "B"
    if r > 195 and g < 70 and b < 70:
        return "R"
    if g > 195 and r < 70 and b < 70:
        return "G"
    if r > 150 and 90 < g < 210 and b < 90:
        return "O"
    if r < 40 and g < 40 and b < 40:
        return "K"
    return "."


# -- Geometry helpers (pure, the selftest drives them directly).


def make_rot(pitch_deg, yaw_deg):
    """world = Ry(yaw) * Rx(pitch) * local. The harness nests the two nodes
    (outer yaw, inner pitch), so Qt's euler order cannot bite the oracle."""
    p = math.radians(pitch_deg)
    y = math.radians(yaw_deg)
    cp, sp = math.cos(p), math.sin(p)
    cy, sy = math.cos(y), math.sin(y)

    def rot(v):
        x, yy, z = v
        y1 = yy * cp - z * sp
        z1 = yy * sp + z * cp
        return (x * cy + z1 * sy, y1, -x * sy + z1 * cy)

    return rot


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def ray(px, py):
    """World ray through a pixel: fixed camera at (0, 0, CAM_Z) looking
    down -Z, vertical FOV 60, aspect VIEW_W/VIEW_H; direction z = -1.

    Written as one quotient around the pixel centre: the row mirror
    py -> VIEW_H - 1 - py negates yn EXACTLY in float (integer numerator,
    single rounding), which is what makes the --selftest mirror probe a
    bit-exact set equality."""
    xn = (2.0 * px + 1.0 - VIEW_W) / VIEW_W
    yn = (VIEW_H - 1.0 - 2.0 * py) / VIEW_H
    return (0.0, 0.0, CAM_Z), (xn * FOV_TAN * ASPECT, yn * FOV_TAN, -1.0)


def _point_in_poly2d(pt, poly):
    x, y = pt
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def build_scene(rot, caps):
    """World frames of the three face quads and the enabled cap planes.
    The bottom cap's 180 X node rotation maps local (x, 0, z) -> (x, 0, -z):
    the ring is symmetric under it, so both caps share the vertex set here
    — that identity is exactly what variants 3 vs 4 measure."""
    faces = []
    for k in range(N):
        theta = TICK * k
        normal = (math.sin(theta), 0.0, math.cos(theta))
        tangent = (math.cos(theta), 0.0, -math.sin(theta))
        center = (APOTHEM * normal[0], 0.0, APOTHEM * normal[2])
        faces.append(
            {
                "kind": "face",
                "class": FACE_CLASSES[k],
                "n": rot(normal),
                "g": rot(tangent),
                # The face quad's vertical axis in WORLD: |rel . up| <= H/2
                # must be measured in the FACE frame, not against the world y
                # (the cube tilt rotates the quad: at pitch 30 a corner sits
                # at world y = +/-630 while its local |y| is 450).
                "up": rot((0.0, 1.0, 0.0)),
                "c": rot(center),
            }
        )
    capsurfaces = []
    for which, y in (("top", HALF_H), ("bottom", -HALF_H)):
        if which not in caps:
            continue
        capsurfaces.append(
            {
                "kind": "cap",
                "which": which,
                "n": rot((0.0, 1.0, 0.0)),
                "p0": rot((0.0, y, 0.0)),
                "e1": rot((1.0, 0.0, 0.0)),
                "e2": rot((0.0, 0.0, 1.0)),
            }
        )
    return faces, capsurfaces


def hits(faces, capsurfaces, o, d):
    """All surface intersections along the ray, nearest first."""
    out = []
    for face in faces:
        denom = _dot(face["n"], d)
        if abs(denom) < 1e-9:
            continue
        t = _dot(face["n"], _sub(face["c"], o)) / denom
        if t <= 0:
            continue
        p = (o[0] + t * d[0], o[1] + t * d[1], o[2] + t * d[2])
        rel = _sub(p, face["c"])
        if abs(_dot(rel, face["g"])) <= HALF_W and abs(_dot(rel, face["up"])) <= HALF_H:
            out.append((t, face))
    for cap in capsurfaces:
        denom = _dot(cap["n"], d)
        if abs(denom) < 1e-9:
            continue
        t = _dot(cap["n"], _sub(cap["p0"], o)) / denom
        if t <= 0:
            continue
        p = (o[0] + t * d[0], o[1] + t * d[1], o[2] + t * d[2])
        rel = _sub(p, cap["p0"])
        if _point_in_poly2d((_dot(rel, cap["e1"]), _dot(rel, cap["e2"])), CAP_POLY):
            out.append((t, cap))
    out.sort(key=lambda hit: hit[0])
    return out


def grid_fronts(pitch, yaw, caps, step=STEP):
    """Front surface per sampled pixel + the scene frames (the grab loop
    reuses them for the outside check without rebuilding anything)."""
    rot = make_rot(pitch, yaw)
    faces, capsurfaces = build_scene(rot, caps)
    fronts = {}
    for py in range(0, VIEW_H, step):
        for px in range(0, VIEW_W, step):
            o, d = ray(px, py)
            hitlist = hits(faces, capsurfaces, o, d)
            fronts[(px, py)] = hitlist[0][1] if hitlist else None
    return fronts, faces, capsurfaces


def analyse(fronts, faces, caps_all, ref_px, var_px):
    """Per-pixel oracle counters over one sampled grid. fronts is the
    front-surface map for the VARIANT's cap set; caps_all carries both cap
    planes so an 'outside' pixel means no cap surface anywhere on its ray
    (a paint that cannot come from the mesh)."""
    metrics = {"cross": 0, "caplost": 0, "gapopen": 0, "outside": 0, "capseen": 0}
    examples = []
    for (px, py), front in fronts.items():
        refc = classify(ref_px(px, py))
        varc = classify(var_px(px, py))
        if front is not None and front["kind"] == "face":
            if refc == front["class"] and varc == "O":
                metrics["cross"] += 1
                examples.append(("cross", px, py))
        elif front is not None and front["kind"] == "cap":
            if varc == "O":
                metrics["capseen"] += 1
            elif refc == "K":
                metrics["gapopen"] += 1
                examples.append(("gapopen", px, py))
            elif refc in FACE_CLASSES and varc == refc:
                metrics["caplost"] += 1
                examples.append(("caplost", px, py))
        if varc == "O" and (front is None or front["kind"] != "cap"):
            o, d = ray(px, py)
            hitlist = hits(faces, caps_all, o, d)
            if not any(h[1]["kind"] == "cap" for h in hitlist):
                metrics["outside"] += 1
                examples.append(("outside", px, py))
    metrics["examples"] = examples[:4]
    return metrics


def cap_mask(px, step=STEP):
    return {
        (x, y)
        for y in range(0, VIEW_H, step)
        for x in range(0, VIEW_W, step)
        if classify(px(x, y)) == "O"
    }


def marker_centroid(px, cells, color_class):
    sx = sy = n = 0
    for x, y in cells:
        if classify(px(x, y)) == color_class:
            sx += x
            sy += y
            n += 1
    return None if n == 0 else (round(sx / n, 1), round(sy / n, 1), n)


# --------------------------------------------------------------------------
# Render child: one process per pitch (the check-video-dome lesson: a second
# QGuiApplication.exec after the first never returned — here there is no exec
# at all: grabWindow() renders synchronously and pump() advances the scene).


def run_child(import_root, pitch, png):
    from PySide6.QtGui import QGuiApplication, QImage, qRgb
    from PySide6.QtQml import QQmlEngine

    application = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    if application.platformName() in ("offscreen", "minimal"):
        print(
            "check-cap-overlap: skipped (needs a real platform; "
            "QtQuick3D does not render offscreen)"
        )
        return 0

    # The asymmetric content probe (mission item 3): orange cap base, a
    # magenta quadrant at the item's top-left, a cyan stripe along the top
    # row. A horizontal mirror moves the QUADRANT to the other x-side; a
    # 180 rotation moves the STRIPE too - the two are never confused.
    if not png.exists():
        image = QImage(256, 256, QImage.Format_RGB32)
        for y in range(256):
            for x in range(256):
                if y < 24:
                    color = (0, 255, 255)
                elif x < 128 and y < 128:
                    color = (255, 0, 255)
                else:
                    color = CAP_RGB
                image.setPixelColor(x, y, qRgb(*color))
        image.save(str(png))

    engine = QQmlEngine()
    engine.addImportPath(str(import_root))
    engine.rootContext().setContextProperty("stubDesktopCount", 3)
    engine.rootContext().setContextProperty("stubFaceCoverage", 1.0)
    view, qml_errors = view_boot(
        f"check-cap-overlap (pitch {pitch:g})",
        engine,
        ROOT / "scripts/check-cap-overlap.qml",
        (VIEW_W, VIEW_H),
        QML_ERROR_SIGNATURES,
    )
    if view is None:
        return 1
    root = view.rootObject()
    root.setProperty("pitch", pitch)
    pump(0.6)

    problems = []
    # Arrow centroids recorded per (pass, yaw) for the mirror-pair assertions
    # after the passes (they compare +30 with -30 and v3 with v4).
    arrow_sig = {}

    def as_px(image):
        def getter(x, y):
            value = image.pixel(x, y)
            return ((value >> 16) & 255, (value >> 8) & 255, value & 255)

        return getter

    def grab():
        pump(0.25)
        return view.grabWindow().convertToFormat(QImage.Format_RGB32)

    def read_snapshot():
        tick = int(root.property("snapshotTick") or 0) + 1
        root.setProperty("snapshotTick", tick)
        pump(0.1)
        return json.loads(str(root.property("snapshot") or "{}"))

    def run_yaw(sub_pitch, yaw):
        root.setProperty("pitch", sub_pitch)
        root.setProperty("yaw", yaw)
        root.setProperty("variant", 0)
        root.setProperty("capContentValue", 0)
        root.setProperty("capImageUrl", "")
        ref_px = as_px(grab())

        # Oracle sanity on the caps-OFF reference: what the geometric front
        # says must be what the engine painted (faces only, no caps here).
        fronts0, _, _ = grid_fronts(sub_pitch, yaw, ())
        seen = agree = 0
        for (x, y), front in fronts0.items():
            refc = classify(ref_px(x, y))
            want = "K" if front is None else front["class"]
            seen += 1
            agree += refc == want
        ratio = agree / max(1, seen)
        print(
            f"[{sub_pitch:g}/{yaw:g}] reference agreement: {ratio:.3f} ({agree}/{seen})"
        )
        if ratio < 0.9:
            print(
                f"FAIL [{sub_pitch:g}/{yaw:g}] oracle disagrees with the "
                "engine on the bare solid"
            )
            problems.append(f"agreement@{sub_pitch:g}/{yaw:g}")

        masks = {}
        for name, (vint, caps_list, opacity) in VARIANTS.items():
            root.setProperty("variant", vint)
            root.setProperty("capOpacity", opacity)
            image = grab()
            var_px = as_px(image)
            fronts, faces, caps_all = grid_fronts(sub_pitch, yaw, caps_list)
            metrics = analyse(fronts, faces, caps_all, ref_px, var_px)
            masks[name] = cap_mask(var_px)
            print(
                f"[{sub_pitch:g}/{yaw:g}] {name:<8} cross={metrics['cross']} "
                f"caplost={metrics['caplost']} gapopen={metrics['gapopen']} "
                f"outside={metrics['outside']} cappix={len(masks[name])}"
            )
            if metrics["examples"]:
                print(f"           examples: {metrics['examples']}")
            for key in ("cross", "caplost", "gapopen", "outside"):
                if metrics[key] > 0:
                    problems.append(f"{name}-{key}@{sub_pitch:g}/{yaw:g}")

        # Variant unions and mirror (assertion c): both == top UNION bottom,
        # and the rotated bottom == the unrotated twin silhouette.
        union = masks["v2top"] | masks["v3bot"]
        sym_both = len(masks["v1@80"] ^ union)
        sym_mirror = len(masks["v3bot"] ^ masks["v4loose"])
        tol_both = max(40, int(0.02 * len(union)))
        tol_mirror = max(40, int(0.02 * max(1, len(masks["v3bot"]))))
        ok = sym_both <= tol_both and sym_mirror <= tol_mirror
        print(
            f"[{sub_pitch:g}/{yaw:g}] masks: both={len(masks['v1@80'])} "
            f"union={len(union)} symdiff={sym_both} | v3={len(masks['v3bot'])} "
            f"v4={len(masks['v4loose'])} mirror-symdiff={sym_mirror} "
            f"(tol {tol_both}/{tol_mirror})"
        )
        if not ok:
            problems.append(f"masks@{sub_pitch:g}/{yaw:g}")

        # Content mirror probe (mission item 3, measured, not asserted):
        # the asymmetric PNG alone on each cap, on the capture rows.
        if abs(sub_pitch) == 30 and yaw in (0.0, 154.0):
            root.setProperty("capContentValue", 2)
            root.setProperty("capImageUrl", png.resolve().as_uri())
            for tag, vint in (("top", 2), ("bottom", 3), ("loose", 4)):
                root.setProperty("variant", vint)
                grab()
                pump(1.0)  # the asynchronous Image decode
                image = grab()
                var_px = as_px(image)
                pixels = {
                    (x, y)
                    for y in range(0, VIEW_H, STEP)
                    for x in range(0, VIEW_W, STEP)
                    if classify(var_px(x, y)) in ("O", "M", "C")
                }
                magenta = marker_centroid(var_px, pixels, "M")
                cyan = marker_centroid(var_px, pixels, "C")
                print(
                    f"[{sub_pitch:g}/{yaw:g}] image-{tag:<6} "
                    f"caparea={len(pixels)} magenta={magenta} cyan={cyan}"
                )
            root.setProperty("capContentValue", 0)
            root.setProperty("capImageUrl", "")

        # Arrow marker probe (CapContent Arrow, the schema default of ADR-027
        # amendment 2): the magenta-quadrant / cyan-arrow centroid table per
        # cap and per yaw. The bottom cap rides eulerRotation.z: 180 — the
        # ring-preserving flip — so its quadrant must land MIRRORED in x (at
        # the same row band) against the unrotated twin of variant 4, and
        # against the top cap at the mirrored row. Anywhere else means the
        # rotation Cube.qml documents is not what the engine applies. The
        # full ±30 sweep carries the table; the other pitches probe yaw 0.
        if abs(sub_pitch) == 30 or yaw == 0.0:
            root.setProperty("capContentValue", 3)
            for tag, vint in (("top", 2), ("bottom", 3), ("loose", 4)):
                root.setProperty("variant", vint)
                grab()
                pump(0.6)  # CapArrow.qml Loader + sourceItem re-grab
                image = grab()
                var_px = as_px(image)
                cells = {
                    (x, y)
                    for y in range(0, VIEW_H, STEP)
                    for x in range(0, VIEW_W, STEP)
                    if classify(var_px(x, y)) in ("O", "M", "C")
                }
                magenta = marker_centroid(var_px, cells, "M")
                arrow = marker_centroid(var_px, cells, "C")
                visible_base = masks.get(
                    {2: "v2top", 3: "v3bot", 4: "v4loose"}[vint], set()
                )
                # The marker is only REQUIRED on a cap seen broadly head-on
                # (measured): on the thin slivers a tilted camera shows, the
                # quadrant — a CORNER of the ring's UV square — lies outside
                # the visible arc by construction (e.g. [60/0] bottom: 168 px
                # near the azimuth-180 gap chord, u ~ 0.50, outside the
                # quadrant's u < 0.42). Requiring it there would assert the
                # UV raster, not the feature.
                if len(visible_base) > 250 and magenta is None:
                    print(
                        f"FAIL [{sub_pitch:g}/{yaw:g}] arrow-{tag}: cap seen "
                        f"({len(visible_base)} px) but the quadrant did not paint"
                    )
                    problems.append(f"arrow-{tag}@{sub_pitch:g}/{yaw:g}")
                arrow_sig[(sub_pitch, yaw, tag)] = (magenta, arrow)
                print(
                    f"[{sub_pitch:g}/{yaw:g}] arrow-{tag:<6} caparea={len(cells)} "
                    f"magenta={magenta} arrow={arrow}"
                )
            root.setProperty("capContentValue", 0)

    # Wiring first: the cap mesh Loader (QtQuick3D.Helpers) must be live,
    # else nothing renders and the gate would be vacuous -> skip honestly.
    root.setProperty("variant", 1)
    root.setProperty("capOpacity", 80)
    snapshot = read_snapshot()
    if not snapshot.get("capsActive") or not snapshot.get("hasMesh"):
        print(
            "check-cap-overlap: skipped (cap mesh not live: "
            "QtQuick3D.Helpers missing or degenerate caps)"
        )
        return 0
    caps = {c["tag"]: c for c in snapshot.get("caps", []) if c.get("present")}
    if (
        "top" not in caps
        or "bottom" not in caps
        or abs(caps["top"]["y"] - HALF_H) > 1e-3
        or abs(caps["bottom"]["y"] + HALF_H) > 1e-3
        or abs(caps["top"]["rx"]) > 1e-3
        # Cube.qml flips the bottom cap around Z (the ring-preserving axis,
        # see the Cube.qml comment): rx/ry must stay 0, rz must be 180.
        or abs(caps["bottom"]["rz"] - 180) > 1e-3
        or abs(caps["bottom"]["ry"]) > 1e-3
        or abs(caps["bottom"]["rx"]) > 1e-3
    ):
        print(f"check-cap-overlap (pitch {pitch:g}): FAIL cap node wiring {caps}")
        return 1
    print(
        f"[p{pitch:g}] wiring: top y={caps['top']['y']:.1f} "
        f"rx={caps['top']['rx']:.0f}, bottom y={caps['bottom']['y']:.1f} "
        f"rz={caps['bottom']['rz']:.0f} (180 = ring-preserving flip), "
        f"apothem={snapshot['faceDistance']:.1f} (capture d=472)"
    )

    # The ADR-027 overlap-fix material contract (structural half of
    # assertion d): opacity >= 0.99 -> Mask with an explicit 0.5 cutoff (the
    # kept fragments WRITE DEPTH, so a centroid tie can no longer paint a
    # far cap over a near face); < 0.99 -> Blend. The pre-fix pilot
    # measured Blend (mask=False) at BOTH opacities: hypothesis confirmed.
    for opacity, want in ((100, "mask"), (80, "blend")):
        root.setProperty("capOpacity", opacity)
        snapshot = read_snapshot()
        caps = {c["tag"]: c for c in snapshot.get("caps", []) if c.get("present")}
        for tag in ("top", "bottom"):
            state = caps[tag]
            ok = (
                state[want]
                and state["hasAlphaMode"]
                and abs(state["opacity"] - opacity / 100) < 1e-5
            )
            if want == "mask":
                ok = ok and abs(state["cutoff"] - 0.5) < 1e-6 and not state["blend"]
            else:
                ok = ok and not state["mask"]
            print(
                f"{'PASS' if ok else 'FAIL'} [p{pitch:g}] cap {tag} at "
                f"CapOpacity {opacity}: alphaMode {want} "
                f"(mask={state['mask']} blend={state['blend']} "
                f"cutoff={state['cutoff']:.2f} opacity={state['opacity']:.2f})"
            )
            if not ok:
                problems.append(f"material-{tag}-{opacity}")

    # Harness pitch p == camera above. The KWin controller's overlay +30
    # sits the camera BELOW (position.y = -r sin 30), i.e. harness -30: the
    # 30 child runs BOTH signs so the table covers the user's real angle.
    passes = [pitch] + ([-pitch] if pitch == 30 else [])
    for sub_pitch in passes:
        for yaw in YAWS:
            run_yaw(sub_pitch, yaw)

    # Mirror-pair numbers (the "gira o espeja" proof, ADR-027 amendment 2).
    # At yaw 0 (scene plane of symmetry = the screen y-axis) the flips must
    # land bit-close:
    #   * v3 vs v4 (same pass): rz180 mirrors u only -> the quadrant x sums
    #     to twice the arrow's x (the u-axis) and the row is IDENTICAL (v
    #     preserved); a rotation would move the quadrant to another corner,
    #     not mirror it in x;
    #   * top@+30 vs bottom@-30: the pitch flip mirrors the rows and the cap
    #     flip mirrors the columns -> both sums around the screen centre.
    if pitch == 30:
        for y_ in (0.0, 180.0):
            b = arrow_sig.get((-30.0, y_, "bottom"))
            l = arrow_sig.get((-30.0, y_, "loose"))
            if b and l and b[0] and l[0] and b[1] and l[1]:
                axis = b[1][0] + l[1][0]
                dx = abs(b[0][0] + l[0][0] - axis)
                dy = abs(b[0][1] - l[0][1])
                ok = dx <= 12 and dy <= 12
                print(
                    f"[p{pitch:g}] u-mirror pair y={y_:g}: bottom=({b[0][0]},{b[0][1]}) "
                    f"loose=({l[0][0]},{l[0][1]}) |dx|={dx:.1f} |dy|={dy:.1f} (tol 12) "
                    f"-> {'PASS' if ok else 'FAIL'}"
                )
                if not ok:
                    problems.append(f"u-mirror@{y_:g}")
        t30 = arrow_sig.get((30.0, 0.0, "top"))
        mb30 = arrow_sig.get((-30.0, 0.0, "bottom"))
        if t30 and mb30 and t30[0] and mb30[0]:
            dx = abs(t30[0][0] + mb30[0][0] - (VIEW_W - 1))
            dy = abs(t30[0][1] + mb30[0][1] - (VIEW_H - 1))
            ok = dx <= 12 and dy <= 12
            print(
                f"[p{pitch:g}] pitch-mirror pair: top@+30=({t30[0][0]},{t30[0][1]}) "
                f"bottom@-30=({mb30[0][0]},{mb30[0][1]}) |dx|={dx:.1f} |dy|={dy:.1f} "
                f"(tol 12) -> {'PASS' if ok else 'FAIL'}"
            )
            if not ok:
                problems.append("pitch-mirror")

    for message in qml_errors:
        print(f"FAIL [p{pitch:g}] qml error: {message}")
    if qml_errors:
        problems.append("qml-errors")
    view.hide()
    view.destroy()
    engine.deleteLater()
    if problems:
        print(f"check-cap-overlap (pitch {pitch:g}): FAIL ({len(problems)} problems)")
        return 1
    print(f"check-cap-overlap (pitch {pitch:g}): OK")
    return 0


# --------------------------------------------------------------------------
# --selftest: the detectors must react to TRUANTED synthetic scenes built
# from the oracle itself (no render needed), and stay silent on the clean
# one. Pattern of the other checks' --selftest: fake the input, demand the
# detection.


def selftest():
    failures = []

    # classify table (the exact blends the 80 % material produces).
    cases = {
        CAP_RGB: "O",
        (255, 102, 0): "O",  # cap 80 % over red
        (204, 153, 0): "O",  # cap 80 % over green
        (204, 102, 0): "O",  # cap 80 % over black (sealed-hole colour)
        (0, 0, 255): "B",
        (255, 0, 0): "R",
        (0, 255, 0): "G",
        (255, 0, 255): "M",
        (0, 255, 255): "C",
        (0, 0, 0): "K",
        (128, 128, 128): ".",
    }
    for rgb, want in cases.items():
        got = classify(rgb)
        if got != want:
            failures.append(f"classify{rgb} = {got}, want {want}")

    pitch, yaw = 30.0, 154.0
    fronts, faces, caps_all = grid_fronts(pitch, yaw, ("top", "bottom"))
    cap_cells = sum(1 for f in fronts.values() if f is not None and f["kind"] == "cap")
    face_cells = sum(
        1 for f in fronts.values() if f is not None and f["kind"] == "face"
    )
    if cap_cells < 50 or face_cells < 500:
        failures.append(
            f"scene at {pitch}/{yaw} too thin to probe (cap {cap_cells}, face {face_cells})"
        )

    def ref_ok(x, y):
        front = fronts[(x, y)]
        if front is None:
            return (0, 0, 0)
        if front["kind"] == "cap":
            # the caps-OFF reference behind a cap pixel shows whatever the
            # face-only front is; reuse the same ray for the truth.
            o, d = ray(x, y)
            hitlist = hits(faces, [], o, d)
            if hitlist:
                return FACE_CLASS_RGB[hitlist[0][1]["class"]]
            return (0, 0, 0)
        return FACE_CLASS_RGB[front["class"]]

    def clean_var(x, y):
        front = fronts[(x, y)]
        if front is None:
            return (0, 0, 0)
        if front["kind"] == "cap":
            return CAP_RGB
        return FACE_CLASS_RGB[front["class"]]

    # 1) clean scene: every counter silent, the cap visibly owns cells.
    clean = analyse(fronts, faces, caps_all, ref_ok, clean_var)
    bad = {k: v for k, v in clean.items() if k not in ("capseen", "examples") and v}
    if bad:
        failures.append(f"clean scene lit up: {bad}")
    if clean["capseen"] < 50:
        failures.append(f"clean scene capseen too small ({clean['capseen']})")

    # 2) crossing: the cap wins every pixel whose true front is a face.
    def crossed(x, y):
        front = fronts[(x, y)]
        if front is not None and front["kind"] == "face":
            return CAP_RGB
        return (0, 0, 0)

    metrics = analyse(fronts, faces, caps_all, ref_ok, crossed)
    if metrics["cross"] < 20:
        failures.append(f"crossing detector blind (cross={metrics['cross']})")

    # 3) gap-open: the cap surface is front, behind it the background, and
    #    the variant paints nothing (the user's "no tapa el hueco").
    metrics = analyse(
        fronts, faces, caps_all, lambda x, y: (0, 0, 0), lambda x, y: (0, 0, 0)
    )
    if metrics["gapopen"] < 1:
        failures.append("gap-open detector blind")

    # 4) cap-lost: the face BEHIND the cap paints last (variant equals the
    #    caps-OFF face reference everywhere the cap is truly in front).
    fronts0, _, _ = grid_fronts(pitch, yaw, ())

    def ref_faces(x, y):
        front = fronts0[(x, y)]
        return FACE_CLASS_RGB[front["class"]] if front is not None else (0, 0, 0)

    metrics = analyse(fronts, faces, caps_all, ref_faces, ref_faces)
    if metrics["caplost"] < 1:
        failures.append("cap-lost detector blind")

    # 5) outside-silhouette: cap colour painted where NO cap surface is on
    #    the ray at all.
    metrics = analyse(fronts, faces, caps_all, ref_ok, lambda x, y: CAP_RGB)
    if metrics["outside"] < 1:
        failures.append("outside-silhouette detector blind")

    # 6) mirror identity of the oracle itself: the top cap's front cells at
    #    pitch +p equal the bottom cap's at -p under the row mirror
    #    py -> VIEW_H - 1 - py (the scene is symmetric under y -> -y about
    #    the camera axis; the single-quotient ray() makes it bit-exact).
    def cap_cells_at(p, y_, which, rows):
        rot = make_rot(p, y_)
        fs, cps = build_scene(rot, (which,))
        cells = set()
        for py in rows:
            for px in range(0, VIEW_W, STEP):
                o, d = ray(px, py)
                hitlist = hits(fs, cps, o, d)
                if hitlist and hitlist[0][1]["kind"] == "cap":
                    cells.add((px, py))
        return cells

    # (yaw 0 only: the y -> -y mirror conjugates Ry to Ry(-yaw), so off zero
    # the scene mirror also needs the yaw flip; at zero it is exact, and at
    # pitch 60 the cap is generously in front.)
    up_rows = list(range(1, VIEW_H - 1, STEP))
    down_rows = [VIEW_H - 1 - y for y in up_rows]
    up = cap_cells_at(60.0, 0.0, "top", up_rows)
    down = cap_cells_at(-60.0, 0.0, "bottom", down_rows)
    down_mirrored = {(x, VIEW_H - 1 - y) for (x, y) in down}
    if len(up) < 50 or up != down_mirrored:
        failures.append(f"oracle mirror mismatch ({len(up)} vs {len(down_mirrored)})")

    return selftest_verdict("check-cap-overlap", failures)


def main(argv):
    if "--pitch" in argv:
        import_root = Path(argv[1])
        pitch = float(argv[argv.index("--pitch") + 1])
        png = Path(argv[argv.index("--png") + 1])
        return run_child(import_root, pitch, png)

    if "--selftest" in argv:
        return selftest()

    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        print(
            "check-cap-overlap: skipped (no display; QtQuick3D needs a real platform)"
        )
        return 0

    scratch_parent = Path("/tmp/opencode") if Path("/tmp/opencode").is_dir() else None
    with tempfile.TemporaryDirectory(
        dir=scratch_parent, prefix="cap-overlap-"
    ) as scratch:
        import_root = _dome.write_stub_module(scratch)
        png = Path(scratch) / "pattern.png"
        problems = 0
        for pitch in PITCHES:
            result = subprocess.run(
                [
                    sys.executable,
                    "-u",
                    str(Path(__file__).resolve()),
                    str(import_root),
                    "--pitch",
                    f"{pitch}",
                    "--png",
                    str(png),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            print(result.stdout, end="")
            qml_errors = [
                line
                for line in (result.stdout + result.stderr).splitlines()
                if any(signature in line for signature in QML_ERROR_SIGNATURES)
                and "qml error:" not in line
            ]
            for message in qml_errors:
                print(f"FAIL [p{pitch:g}] qml error (parent scan): {message}")
            if result.returncode != 0:
                if result.stderr:
                    print(result.stderr, end="", file=sys.stderr)
                problems += 1
            elif qml_errors:
                problems += 1
        if problems:
            print(f"check-cap-overlap: FAIL ({problems} pitch child(s))")
            return 1
        print(
            "check-cap-overlap: OK (no cap bleed over nearer faces, no paint outside "
            "the cap ring, holes sealed, both = top union bottom, rotated = unrotated "
            "silhouette; material Mask at 100 / Blend at 80; arrow marker painted)"
        )
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
