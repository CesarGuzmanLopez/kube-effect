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

The geometric oracle (front surface per sampled pixel) lives in
cap_overlap_oracle.py (pure Python, no Qt) and
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
import os
import shutil
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=DeprecationWarning)

from cap_overlap_oracle import (
    CAP_RGB,
    MIRROR_PROBE_PITCH,
    PITCHES,
    VARIANTS,
    VIEW_H,
    VIEW_W,
    _marker_cells,
    _material_state_ok,
    _wiring_violations,
    analyse,
    cap_mask,
    classify,
    grid_fronts,
    marker_centroid,
    selftest,
    sweep_rows,
)
from qml_check_harness import (
    QML_ERROR_SIGNATURES,
    ROOT,
    pump,
    require_pyside,
    view_boot,
)

require_pyside("check-cap-overlap")

_spec = importlib.util.spec_from_file_location(
    "check_video_dome_for_stubs", ROOT / "scripts/check-video-dome.py"
)
_dome = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_dome)

# --------------------------------------------------------------------------
# Render child: one process per pitch (the check-video-dome lesson: a second
# QGuiApplication.exec after the first never returned — here there is no exec
# at all: grabWindow() renders synchronously and pump() advances the scene).


def as_px(image):
    """RGB32 pixel getter over a QImage, as the counters consume it."""

    def getter(x, y):
        value = image.pixel(x, y)
        return ((value >> 16) & 255, (value >> 8) & 255, value & 255)

    return getter


def grab(view):
    pump(0.25)
    from PySide6.QtGui import QImage

    return view.grabWindow().convertToFormat(QImage.Format_RGB32)


def read_snapshot(root):
    tick = int(root.property("snapshotTick") or 0) + 1
    root.setProperty("snapshotTick", tick)
    pump(0.1)
    return json.loads(str(root.property("snapshot") or "{}"))


def _make_pattern_png(png):
    # The asymmetric content probe (mission item 3): orange cap base, a
    # magenta quadrant at the item's top-left, a cyan stripe along the top
    # row. A horizontal mirror moves the QUADRANT to the other x-side; a
    # 180 rotation moves the STRIPE too - the two are never confused.
    if png.exists():
        return
    from PySide6.QtGui import QImage, qRgb

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


def _reference_agreement(ref_px, sub_pitch, yaw, problems):
    """Oracle sanity on the caps-OFF reference: what the geometric front
    says must be what the engine painted (faces only, no caps here)."""
    fronts0, _, _ = grid_fronts(sub_pitch, yaw, ())
    seen = agree = 0
    for (x, y), front in fronts0.items():
        refc = classify(ref_px(x, y))
        want = "K" if front is None else front["class"]
        seen += 1
        agree += refc == want
    ratio = agree / max(1, seen)
    print(f"[{sub_pitch:g}/{yaw:g}] reference agreement: {ratio:.3f} ({agree}/{seen})")
    if ratio < 0.9:
        print(
            f"FAIL [{sub_pitch:g}/{yaw:g}] oracle disagrees with the "
            "engine on the bare solid"
        )
        problems.append(f"agreement@{sub_pitch:g}/{yaw:g}")


def _sweep_variants(view, root, ref_px, sub_pitch, yaw, problems):
    """The VARIANTS table over this row; returns the cap masks per name."""
    masks = {}
    for name, (vint, caps_list, opacity) in VARIANTS.items():
        root.setProperty("variant", vint)
        root.setProperty("capOpacity", opacity)
        var_px = as_px(grab(view))
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
    return masks


def _mask_consistency(sub_pitch, yaw, masks, problems):
    """Variant unions and mirror (assertion c): both == top UNION bottom,
    and the rotated bottom == the unrotated twin silhouette."""
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


def _image_probe(view, root, png, sub_pitch, yaw):
    """Content mirror probe (mission item 3, measured, not asserted):
    the asymmetric PNG alone on each cap, on the capture rows."""
    root.setProperty("capContentValue", 2)
    root.setProperty("capImageUrl", png.resolve().as_uri())
    for tag, vint in (("top", 2), ("bottom", 3), ("loose", 4)):
        root.setProperty("variant", vint)
        grab(view)
        pump(1.0)  # the asynchronous Image decode
        var_px = as_px(grab(view))
        pixels = _marker_cells(var_px)
        magenta = marker_centroid(var_px, pixels, "M")
        cyan = marker_centroid(var_px, pixels, "C")
        print(
            f"[{sub_pitch:g}/{yaw:g}] image-{tag:<6} "
            f"caparea={len(pixels)} magenta={magenta} cyan={cyan}"
        )
    root.setProperty("capContentValue", 0)
    root.setProperty("capImageUrl", "")


def _arrow_probe(view, root, sub_pitch, yaw, masks, arrow_sig, problems):
    # Arrow marker probe (CapContent Arrow, the schema default of ADR-027
    # amendment 2): the magenta-quadrant / cyan-arrow centroid table per
    # cap and per yaw. The bottom cap rides eulerRotation.z: 180 — the
    # ring-preserving flip — so its quadrant must land MIRRORED in x (at
    # the same row band) against the unrotated twin of variant 4, and
    # against the top cap at the mirrored row. Anywhere else means the
    # rotation Cube.qml documents is not what the engine applies. The
    # full ±30 sweep carries the table; the other pitches probe yaw 0.
    root.setProperty("capContentValue", 3)
    for tag, vint in (("top", 2), ("bottom", 3), ("loose", 4)):
        root.setProperty("variant", vint)
        grab(view)
        pump(0.6)  # CapArrow.qml Loader + sourceItem re-grab
        var_px = as_px(grab(view))
        cells = _marker_cells(var_px)
        magenta = marker_centroid(var_px, cells, "M")
        arrow = marker_centroid(var_px, cells, "C")
        visible_base = masks.get({2: "v2top", 3: "v3bot", 4: "v4loose"}[vint], set())
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


def run_yaw(
    view, root, png, sub_pitch, yaw, image_probe, arrow_probe, problems, arrow_sig
):
    """One capture row: reference, the variant sweep, mask consistency and
    the marker probes their table flags enable (S1244: no float gate here)."""
    root.setProperty("pitch", sub_pitch)
    root.setProperty("yaw", yaw)
    root.setProperty("variant", 0)
    root.setProperty("capContentValue", 0)
    root.setProperty("capImageUrl", "")
    ref_px = as_px(grab(view))
    _reference_agreement(ref_px, sub_pitch, yaw, problems)
    masks = _sweep_variants(view, root, ref_px, sub_pitch, yaw, problems)
    _mask_consistency(sub_pitch, yaw, masks, problems)
    if image_probe:
        _image_probe(view, root, png, sub_pitch, yaw)
    if arrow_probe:
        _arrow_probe(view, root, sub_pitch, yaw, masks, arrow_sig, problems)


def _wiring_gate(root, pitch):
    # Wiring first: the cap mesh Loader (QtQuick3D.Helpers) must be live,
    # else nothing renders and the gate would be vacuous -> skip honestly.
    # Returns an early exit code, or None when the sweep may run.
    root.setProperty("variant", 1)
    root.setProperty("capOpacity", 80)
    snapshot = read_snapshot(root)
    if not snapshot.get("capsActive") or not snapshot.get("hasMesh"):
        print(
            "check-cap-overlap: skipped (cap mesh not live: "
            "QtQuick3D.Helpers missing or degenerate caps)"
        )
        return 0
    caps = {c["tag"]: c for c in snapshot.get("caps", []) if c.get("present")}
    if _wiring_violations(caps):
        print(f"check-cap-overlap (pitch {pitch:g}): FAIL cap node wiring {caps}")
        return 1
    print(
        f"[p{pitch:g}] wiring: top y={caps['top']['y']:.1f} "
        f"rx={caps['top']['rx']:.0f}, bottom y={caps['bottom']['y']:.1f} "
        f"rz={caps['bottom']['rz']:.0f} (180 = ring-preserving flip), "
        f"apothem={snapshot['faceDistance']:.1f} (capture d=472)"
    )
    return None


def _material_gate(root, pitch, problems):
    # The ADR-027 overlap-fix material contract (structural half of
    # assertion d): opacity >= 0.99 -> Mask with an explicit 0.5 cutoff (the
    # kept fragments WRITE DEPTH, so a centroid tie can no longer paint a
    # far cap over a near face); < 0.99 -> Blend. The pre-fix pilot
    # measured Blend (mask=False) at BOTH opacities: hypothesis confirmed.
    for opacity, want in ((100, "mask"), (80, "blend")):
        root.setProperty("capOpacity", opacity)
        snapshot = read_snapshot(root)
        caps = {c["tag"]: c for c in snapshot.get("caps", []) if c.get("present")}
        for tag in ("top", "bottom"):
            state = caps[tag]
            ok = _material_state_ok(state, opacity, want)
            print(
                f"{'PASS' if ok else 'FAIL'} [p{pitch:g}] cap {tag} at "
                f"CapOpacity {opacity}: alphaMode {want} "
                f"(mask={state['mask']} blend={state['blend']} "
                f"cutoff={state['cutoff']:.2f} opacity={state['opacity']:.2f})"
            )
            if not ok:
                problems.append(f"material-{tag}-{opacity}")


def _u_mirror_pairs(pitch, arrow_sig, problems):
    # v3 vs v4 (same pass): rz180 mirrors u only -> the quadrant x sums
    # to twice the arrow's x (the u-axis) and the row is IDENTICAL (v
    # preserved); a rotation would move the quadrant to another corner,
    # not mirror it in x.
    for y_ in (0, 180):
        b = arrow_sig.get((-pitch, y_, "bottom"))
        l = arrow_sig.get((-pitch, y_, "loose"))
        if not (b and l and b[0] and l[0] and b[1] and l[1]):
            continue
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


def _pitch_mirror_pair(pitch, arrow_sig, problems):
    # top@+30 vs bottom@-30: the pitch flip mirrors the rows and the cap
    # flip mirrors the columns -> both sums around the screen centre.
    t30 = arrow_sig.get((pitch, 0, "top"))
    mb30 = arrow_sig.get((-pitch, 0, "bottom"))
    if not (t30 and mb30 and t30[0] and mb30[0]):
        return
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


def _mirror_pairs(pitch, arrow_sig, problems):
    # Mirror-pair numbers (the "gira o espeja" proof, ADR-027 amendment 2).
    # At yaw 0 (scene plane of symmetry = the screen y-axis) the flips must
    # land bit-close; each pair is only asserted when both centroids
    # actually painted.
    if pitch != MIRROR_PROBE_PITCH:
        return
    _u_mirror_pairs(pitch, arrow_sig, problems)
    _pitch_mirror_pair(pitch, arrow_sig, problems)


def run_child(import_root, pitch, png):
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlEngine

    application = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    if application.platformName() in ("offscreen", "minimal"):
        print(
            "check-cap-overlap: skipped (needs a real platform; "
            "QtQuick3D does not render offscreen)"
        )
        return 0

    _make_pattern_png(png)

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

    early = _wiring_gate(root, pitch)
    if early is not None:
        return early

    _material_gate(root, pitch, problems)

    for sub_pitch, yaw, image_probe, arrow_probe in sweep_rows(pitch):
        run_yaw(
            view,
            root,
            png,
            sub_pitch,
            yaw,
            image_probe,
            arrow_probe,
            problems,
            arrow_sig,
        )

    _mirror_pairs(pitch, arrow_sig, problems)

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


def _scratch_root():
    """Private base for the throwaway QML module and pattern PNG.

    Never the bare world-writable /tmp (the hotspot the old dir=None
    fallback created). Contract: {TMPDIR:-/tmp/opencode}; a missing
    base is created 0700; a symlink, a foreign owner or a base others could
    write into is refused outright (the rule nested-harness-root.sh
    enforces). Returns (path, None) or (None, reason) so main() can skip
    with exit 0.
    """
    base = Path(os.environ.get("TMPDIR") or "/tmp/opencode")
    if base.is_symlink():
        return None, f"{base} is a symlink"
    if not base.is_dir():
        try:
            base.mkdir(mode=0o700, parents=True)
        except OSError as exc:
            return None, f"cannot create {base} ({exc.strerror})"
    st = base.stat()
    if st.st_uid != os.getuid():
        return None, f"{base} is not owned by uid {os.getuid()}"
    # Own the base is NOT enough: a group/world-writable directory of ours
    # still lets any local user plant the stub module or the pattern PNG we
    # are about to read (measured before this branch: a 0777 dir owned by us
    # passed the old `uid != uid AND 0o022` test, which only fired for
    # foreign-owned bases). Normalise our own directory to 0700 instead of
    # refusing it, exactly like nested-harness-root.sh chmods its root.
    if st.st_mode & 0o077:
        try:
            base.chmod(0o700)
        except OSError as exc:
            return None, f"cannot tighten {base} to 0700 ({exc.strerror})"
        st = base.stat()
        if st.st_mode & 0o077:
            return None, f"{base} stays group/world writable"
    if not os.access(base, os.W_OK | os.X_OK):
        return None, f"{base} is not writable by us"
    return base, None


def _st_case(root, name, mode=None, symlink_of=None):
    """Builds one hostile scratch base and returns (path, cleanup).

    The bases live INSIDE the already validated scratch root, so the test
    never touches a directory it has not vetted; only the TMPDIR variable
    points at them, which is exactly what _scratch_root() must survive.
    """
    base = root / name
    if base.is_symlink() or base.exists():
        if base.is_symlink() or base.is_file():
            base.unlink()
        else:
            shutil.rmtree(base)
    if symlink_of is not None:
        base.symlink_to(symlink_of)
    else:
        base.mkdir(mode=0o700, parents=True)
        if mode is not None:
            os.chmod(base, mode)
    return base


def _st_expect_refuse(label, base, failures):
    """Runs _scratch_root() with TMPDIR=base and demands a refusal."""
    saved = os.environ.get("TMPDIR")
    os.environ["TMPDIR"] = str(base)
    try:
        got, _why = _scratch_root()
    finally:
        if saved is None:
            os.environ.pop("TMPDIR", None)
        else:
            os.environ["TMPDIR"] = saved
    if got is not None:
        failures.append(f"{label} accepted: {got}")
    return got


def _scratch_selftest():
    """Regression tests for _scratch_root(), the anti-hijack contract.

    The pixel gate loads a QML stub module and a pattern PNG out of this
    directory, so a base another local user can write into is code execution
    as us, not just a broken check. Measured gap that started this: the first
    version only refused FOREIGN-owned writable bases, so a 0777 directory
    owned by us passed.
    """
    failures = []
    root, why = _scratch_root()
    if root is None:
        return [f"no usable scratch base on this machine ({why})"]

    # 1. ours but group/world writable -> ACCEPTED and tightened to 0700 (the
    #    nested harness chmods its own root the same way).
    loose = _st_case(root, "st-scratch-loose", mode=0o777)
    saved = os.environ.get("TMPDIR")
    os.environ["TMPDIR"] = str(loose)
    try:
        got, _ = _scratch_root()
    finally:
        if saved is None:
            os.environ.pop("TMPDIR", None)
        else:
            os.environ["TMPDIR"] = saved
    if got is None:
        failures.append("0777 base of ours was refused instead of tightened")
    elif os.stat(loose).st_mode & 0o077:
        failures.append(
            f"0777 base stayed loose: {oct(os.stat(loose).st_mode & 0o777)}"
        )

    # 2. symlink base -> refused, never followed.
    victim = _st_case(root, "st-scratch-victim")
    link = _st_case(root, "st-scratch-link", symlink_of=victim)
    _st_expect_refuse("symlink base", link, failures)

    # 3. base owned by ANOTHER uid -> refused. A real second user (or root) is
    #    not available here, so the branch under test is exercised by
    #    pretending we are somebody else: os.getuid() is what the code
    #    compares, not os.stat().
    real_getuid = os.getuid
    try:
        os.getuid = lambda: real_getuid() + 1
        _st_expect_refuse("foreign-owned base", victim, failures)
    finally:
        os.getuid = real_getuid

    # 4. the bare world-writable /tmp -> refused (only asserted when /tmp
    #    really is world-writable, which holds on the distros running this).
    if os.stat("/tmp").st_mode & 0o022:
        _st_expect_refuse("bare /tmp", Path("/tmp"), failures)

    for stale in (link, loose, victim):
        try:
            if stale.is_symlink() or stale.is_file():
                stale.unlink()
            else:
                shutil.rmtree(stale, ignore_errors=True)
        except OSError:
            pass
    return failures


def _run_pitch_child(pitch, import_root, png):
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
        return 1
    return 1 if qml_errors else 0


def main(argv):
    if "--pitch" in argv:
        import_root = Path(argv[1])
        pitch = int(float(argv[argv.index("--pitch") + 1]))
        png = Path(argv[argv.index("--png") + 1])
        return run_child(import_root, pitch, png)

    if "--selftest" in argv:
        # The scratch-root contract is checked BEFORE the oracle verdict so
        # the printed line stays the last one (the label is part of the gate
        # contract of the other checks).
        scratch_failures = _scratch_selftest()
        if scratch_failures:
            for failure in scratch_failures:
                print(" - " + failure)
            print("check-cap-overlap --selftest: FAIL")
            return 1
        return selftest()

    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        print(
            "check-cap-overlap: skipped (no display; QtQuick3D needs a real platform)"
        )
        return 0

    scratch_root, why = _scratch_root()
    if scratch_root is None:
        print(f"check-cap-overlap: skipped (scratch dir unusable: {why})")
        return 0
    with tempfile.TemporaryDirectory(
        dir=scratch_root, prefix="cap-overlap-"
    ) as scratch:
        import_root = _dome.write_stub_module(scratch)
        png = Path(scratch) / "pattern.png"
        problems = sum(_run_pitch_child(pitch, import_root, png) for pitch in PITCHES)
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
