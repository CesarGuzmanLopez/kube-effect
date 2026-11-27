#!/usr/bin/env python3
"""Pure geometric oracle for the ADR-027 cap pixel gate (no Qt, no display).

Lives apart from check-cap-overlap.py (the render driver) exactly like
cap_contract.py apart from check-cap.py: everything here is computable in
CI without PySide6, a GPU or a screen:

  * the harness geometry constants (mirror of check-cap-overlap.qml),
  * the front-surface raycaster (faces + cap planes, shared cap ring),
  * the per-pixel counters (cross / caplost / gapopen / outside / capseen),
  * the scenario table with the explicit probe flags (S1244: integer
    degrees, booleans instead of float equality),
  * the material/wiring threshold rules,
  * and the --selftest that drives all of it with SYNTHETIC grabs built
    FROM the oracle (a validator that cannot light up on truanted scenes
    is worthless).

Run directly for the selftest:  python3 scripts/cap_overlap_oracle.py --selftest
The gate's meaning, prints and counters are documented in the driver.
"""

import math
import sys

from cap_contract import cap_ring
from qml_check_harness import selftest_verdict

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

# Sweep degrees are integers so the scenario table below (and every gate
# derived from it) never compares floats (S1244); the QML properties take
# them as-is and render identically to the old float tuples.
PITCHES = (0, 15, 30, 45, 60)
YAWS = (0, 60, 120, 154, 180, 240, 300)
MIRROR_PROBE_PITCH = 30  # the user's capture angle: ±signs run, probes gate
IMAGE_PROBE_YAWS = (0, 154)  # the asymmetric-PNG content probe rows
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


def _ray_has_no_cap(px, py, faces, caps_all):
    """True when NO cap surface of the full cap set lies on this pixel's ray."""
    o, d = ray(px, py)
    return not any(h[1]["kind"] == "cap" for h in hits(faces, caps_all, o, d))


def _pixel_events(front, refc, varc, px, py, faces, caps_all):
    """The counters one sampled pixel triggers (one entry per increment).

    A face pixel can light 'cross' AND 'outside' in the same pass (the cap
    colour painted over a front face with no cap surface on the ray), so
    this returns a list, mirroring the counter chain of the original loop.
    """
    events = []
    if front is not None and front["kind"] == "face":
        if refc == front["class"] and varc == "O":
            events.append("cross")
    elif front is not None and front["kind"] == "cap":
        if varc == "O":
            events.append("capseen")
        elif refc == "K":
            events.append("gapopen")
        elif refc in FACE_CLASSES and varc == refc:
            events.append("caplost")
    if (
        varc == "O"
        and (front is None or front["kind"] != "cap")
        and _ray_has_no_cap(px, py, faces, caps_all)
    ):
        events.append("outside")
    return events


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
        for event in _pixel_events(front, refc, varc, px, py, faces, caps_all):
            metrics[event] += 1
            if event != "capseen":  # counted, never exampled (see the sweep)
                examples.append((event, px, py))
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


def _marker_cells(var_px):
    """The probe cell set: cap-or-marker pixels on the sampled grid."""
    return {
        (x, y)
        for y in range(0, VIEW_H, STEP)
        for x in range(0, VIEW_W, STEP)
        if classify(var_px(x, y)) in ("O", "M", "C")
    }


def sweep_rows(pitch):
    """Capture rows for one child: (sub_pitch, yaw, image_probe, arrow_probe).

    The two probe gates used to be float comparisons inside the sweep
    ("abs(sub_pitch) == 30 and yaw in (0.0, 154.0)" /
    "abs(sub_pitch) == 30 or yaw == 0.0", S1244). They are explicit booleans
    on this scenario table now, derived from the integer sweep degrees:

      * image_probe (the asymmetric PNG): |sub_pitch| == 30 and yaw in (0, 154);
      * arrow_probe (CapContent Arrow):   |sub_pitch| == 30 or  yaw == 0.

    Harness pitch p == camera above. The KWin controller's overlay +30 sits
    the camera BELOW (position.y = -r sin 30), i.e. harness -30: the 30
    child runs BOTH signs so the table covers the user's real angle.
    """
    rows = []
    for sign in (1, -1) if pitch == MIRROR_PROBE_PITCH else (1,):
        for yaw in YAWS:
            sub_pitch = sign * pitch
            flipped = abs(sub_pitch) == MIRROR_PROBE_PITCH
            image_probe = flipped and yaw in IMAGE_PROBE_YAWS
            arrow_probe = flipped or yaw == 0
            rows.append((sub_pitch, yaw, image_probe, arrow_probe))
    return rows


def _wiring_violations(caps):
    """Cap node wiring: both planes present, at y = ±H/2, top unrotated,
    bottom flipped around Z (the ring-preserving axis, see the Cube.qml
    comment): rx/ry must stay 0, rz must be 180. One condition per row."""
    missing = [f"no {t} cap" for t in ("top", "bottom") if t not in caps]
    checks = (
        ("top", "y", HALF_H),
        ("bottom", "y", -HALF_H),
        ("top", "rx", 0.0),
        ("bottom", "rx", 0.0),
        ("bottom", "ry", 0.0),
        ("bottom", "rz", 180.0),
    )
    return missing + [
        f"{tag}.{key}={caps[tag][key]} want {want}"
        for tag, key, want in checks
        if tag in caps and abs(caps[tag][key] - want) > 1e-3
    ]


def _material_state_ok(state, opacity, want):
    """One cap node's material contract at one opacity (assertion d)."""
    ok = (
        state[want]
        and state["hasAlphaMode"]
        and abs(state["opacity"] - opacity / 100) < 1e-5
    )
    if want == "mask":
        return ok and abs(state["cutoff"] - 0.5) < 1e-6 and not state["blend"]
    return ok and not state["mask"]


def _st_classify():
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
    failures = []
    for rgb, want in cases.items():
        got = classify(rgb)
        if got != want:
            failures.append(f"classify{rgb} = {got}, want {want}")
    return failures


def _ref_ok_getter(fronts, faces):
    # The caps-OFF reference behind a cap pixel shows whatever the face-only
    # front is; reuse the same ray for the truth.
    def ref_ok(x, y):
        front = fronts[(x, y)]
        if front is None:
            return (0, 0, 0)
        if front["kind"] == "cap":
            o, d = ray(x, y)
            hitlist = hits(faces, [], o, d)
            if hitlist:
                return FACE_CLASS_RGB[hitlist[0][1]["class"]]
            return (0, 0, 0)
        return FACE_CLASS_RGB[front["class"]]

    return ref_ok


def _st_clean(fronts, faces, caps_all, ref_ok):
    # 1) clean scene: every counter silent, the cap visibly owns cells.
    def clean_var(x, y):
        front = fronts[(x, y)]
        if front is None:
            return (0, 0, 0)
        if front["kind"] == "cap":
            return CAP_RGB
        return FACE_CLASS_RGB[front["class"]]

    failures = []
    clean = analyse(fronts, faces, caps_all, ref_ok, clean_var)
    bad = {k: v for k, v in clean.items() if k not in ("capseen", "examples") and v}
    if bad:
        failures.append(f"clean scene lit up: {bad}")
    if clean["capseen"] < 50:
        failures.append(f"clean scene capseen too small ({clean['capseen']})")
    return failures


def _st_crossing(fronts, faces, caps_all, ref_ok):
    # 2) crossing: the cap wins every pixel whose true front is a face.
    def crossed(x, y):
        front = fronts[(x, y)]
        if front is not None and front["kind"] == "face":
            return CAP_RGB
        return (0, 0, 0)

    metrics = analyse(fronts, faces, caps_all, ref_ok, crossed)
    if metrics["cross"] < 20:
        return [f"crossing detector blind (cross={metrics['cross']})"]
    return []


def _st_blindness(fronts, faces, caps_all, ref_ok):
    # 3) gap-open: the cap surface is front, behind it the background, and
    #    the variant paints nothing (the user's "no tapa el hueco").
    # 5) outside-silhouette: cap colour painted where NO cap surface is on
    #    the ray at all.
    failures = []
    metrics = analyse(
        fronts, faces, caps_all, lambda x, y: (0, 0, 0), lambda x, y: (0, 0, 0)
    )
    if metrics["gapopen"] < 1:
        failures.append("gap-open detector blind")
    metrics = analyse(fronts, faces, caps_all, ref_ok, lambda x, y: CAP_RGB)
    if metrics["outside"] < 1:
        failures.append("outside-silhouette detector blind")
    return failures


def _st_caplost(fronts, faces, caps_all, pitch, yaw):
    # 4) cap-lost: the face BEHIND the cap paints last (variant equals the
    #    caps-OFF face reference everywhere the cap is truly in front).
    fronts0, _, _ = grid_fronts(pitch, yaw, ())

    def ref_faces(x, y):
        front = fronts0[(x, y)]
        return FACE_CLASS_RGB[front["class"]] if front is not None else (0, 0, 0)

    metrics = analyse(fronts, faces, caps_all, ref_faces, ref_faces)
    if metrics["caplost"] < 1:
        return ["cap-lost detector blind"]
    return []


def _st_mirror_identity():
    # 6) mirror identity of the oracle itself: the top cap's front cells at
    #    pitch +p equal the bottom cap's at -p under the row mirror
    #    py -> VIEW_H - 1 - py (the scene is symmetric under y -> -y about
    #    the camera axis; the single-quotient ray() makes it bit-exact).
    # (yaw 0 only: the y -> -y mirror conjugates Ry to Ry(-yaw), so off zero
    # the scene mirror also needs the yaw flip; at zero it is exact, and at
    # pitch 60 the cap is generously in front.)
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

    up_rows = list(range(1, VIEW_H - 1, STEP))
    down_rows = [VIEW_H - 1 - y for y in up_rows]
    up = cap_cells_at(60.0, 0.0, "top", up_rows)
    down = cap_cells_at(-60.0, 0.0, "bottom", down_rows)
    down_mirrored = {(x, VIEW_H - 1 - y) for (x, y) in down}
    if len(up) < 50 or up != down_mirrored:
        return [f"oracle mirror mismatch ({len(up)} vs {len(down_mirrored)})"]
    return []


def selftest():
    failures = []

    failures.extend(_st_classify())

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

    ref_ok = _ref_ok_getter(fronts, faces)
    failures.extend(_st_clean(fronts, faces, caps_all, ref_ok))
    failures.extend(_st_crossing(fronts, faces, caps_all, ref_ok))
    failures.extend(_st_blindness(fronts, faces, caps_all, ref_ok))
    failures.extend(_st_caplost(fronts, faces, caps_all, pitch, yaw))
    failures.extend(_st_mirror_identity())

    return selftest_verdict("check-cap-overlap", failures)


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else 0)
