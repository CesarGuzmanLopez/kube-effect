/*
    SPDX-FileCopyrightText: 2023 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

// Matches the Background enum in config/main.xml
const Background = {
    Color: 0,
    // Index 1 used to be named SkyBox; kwinrc stores the index, not the name.
    Image: 1,
    Gradient: 2,
    // Appended as index 3 so the stored 0/1/2 keep their meaning. Video is an
    // image whose source is a clip: same layout/fit/rotate keys.
    Video: 3
};
// Matches the BackgroundImageLayout enum in config/main.xml. Auto was
// removed (ADR-013): the user states whether the picture is a panorama. The
// KEY (not just the choices) was renamed on purpose: kwinrc keeps the index,
// so an old BackgroundImageMapping=1 stays orphaned instead of being read back
// as Flat (it used to mean Equirect under the 0=Auto, 1=Equirect, 2=Flat
// scheme).
const BackgroundImageLayout = {
    Equirect: 0,
    Flat: 1
};
// Matches the BackgroundImageFit enum in config/main.xml
const BackgroundImageFit = {
    Cover: 0,
    Contain: 1,
    Stretch: 2
};
// Default BackgroundImageFit / DimWhileRotatingAmount / BackgroundGradientStop
// from config/main.xml, used when the stored value is not a usable number.
const DEFAULT_IMAGE_FIT = BackgroundImageFit.Cover;
const DEFAULT_DIM_AMOUNT = 40;
const DEFAULT_GRADIENT_STOP = 50;
// Matches the BackgroundGradientType enum in config/main.xml
const BackgroundGradientType = {
    LinearVertical: 0,
    LinearHorizontal: 1,
    Radial: 2
};
// Matches the BackgroundGradientRotation enum in config/main.xml. Only the
// gradient hull uses it (ADR-017): the layer may stay still or turn with the
// cube, forwards or backwards.
const BackgroundGradientRotation = {
    Fixed: 0,
    FollowCube: 1,
    FollowCubeInverse: 2
};
// Matches the Shape enum in config/main.xml (ADR-025). Polygon is the virgin
// KDE cube (flat faces on an N-gon); Cylinder bends the same faces into arcs
// on a cylinder. Neither is read below 3 desktops: the sheet always wins
// (ADR-024), so this table never needs to model that case.
const Shape = {
    Polygon: 0,
    Cylinder: 1
};

// An unknown value (kwinrc edited by hand) falls back to a solid colour
// instead of leaving the hull unpainted.
function backgroundMode(value) {
    if (value === Background.Image || value === Background.Gradient || value === Background.Video) {
        return value;
    }
    return Background.Color;
}

// Human-readable Background name for the debug overlay (ADR-023). The chain
// mirrors the enum above instead of trusting object key order; an unknown
// value says "Unknown" — a diagnostic line must never print "undefined"
// where a mode name belongs.
function backgroundName(value) {
    if (value === Background.Image) {
        return "Image";
    }
    if (value === Background.Gradient) {
        return "Gradient";
    }
    if (value === Background.Video) {
        return "Video";
    }
    if (value === Background.Color) {
        return "Color";
    }
    return "Unknown";
}

// An unknown Shape value (kwinrc edited by hand) falls back to the polygon:
// the virgin cube look must survive a bad entry, exactly like backgroundMode
// keeps a hull painted. The sub-3 override is Cube's job (ADR-024), not
// this resolver's.
function shape(value) {
    if (value === Shape.Cylinder) {
        return Shape.Cylinder;
    }
    return Shape.Polygon;
}

// Human-readable Shape name for the debug overlay (ADR-023), in the short
// form the overlay wants ("shape=poly|cyl"). The chain mirrors the enum
// instead of trusting key order (the backgroundName pattern); an unknown
// value says so rather than printing "undefined".
function shapeName(value) {
    if (value === Shape.Cylinder) {
        return "cyl";
    }
    if (value === Shape.Polygon) {
        return "poly";
    }
    return "Unknown";
}

// Equirect is the default and the safe fallback: only an explicit Flat turns
// it off. A hand-edited kwinrc value or a missing entry resolves to equirect;
// stretching a real panorama as a flat photo is worse than wrapping a photo
// around the scene. Values left over from the old key never reach this helper
// (KConfig drops the orphaned key), so an old "1" cannot turn into Flat.
// hasImage no longer influences the decision (the SkyBox still requires an
// image, see skyBoxBackground); it stays in the signature for callers/tests.
function usesEquirectMapping(mapping, hasImage) {
    return mapping !== BackgroundImageLayout.Flat;
}

// Flat-image fit: unknown values fall back to Cover, the schema default.
function imageFit(value) {
    if (value === BackgroundImageFit.Contain || value === BackgroundImageFit.Stretch) {
        return value;
    }
    return DEFAULT_IMAGE_FIT;
}

// Finite test with the same coercion as the historical isFinite(): KConfig
// values can arrive as strings and Number.isFinite() would reject them. Every
// helper here reads a raw kwinrc entry, so the finite guard must accept "50"
// exactly as the global isFinite did; the local Number() coercion is kept
// inside this one place so no call site has to remember the difference.
function isFiniteNumber(value) {
    return Number.isFinite(Number(value));
}

// Number(null) and Number("") are 0, not NaN: a KConfig value that was never
// saved (null/empty) would otherwise clamp to the RANGE FLOOR instead of the
// schema default of the active branch (ADR-022). Parse to a finite number, or
// null when there is no usable value.
function finiteOr(nullable) {
    if (nullable === null || nullable === undefined) {
        return null;
    }
    // A whitespace-only string is "unset" too: Number(" ") is 0, which the
    // floor clamps would take as a real minimum (ADR-022, second review).
    if (typeof nullable === "string" && nullable.trim() === "") {
        return null;
    }
    const value = Number(nullable);
    return Number.isFinite(value) ? value : null;
}

// Opacity of the black veil drawn over the hull while the cube rotates:
// 0 when DimWhileRotating is off, otherwise amount/100 clamped to 0..1. A
// missing or non-numeric amount uses the schema default (40 %).
function dimOpacity(enabled, amount) {
    if (enabled !== true) {
        return 0;
    }
    let percent = finiteOr(amount);
    if (percent === null) {
        percent = DEFAULT_DIM_AMOUNT;
    }
    return Math.min(1, Math.max(0, percent / 100));
}

// Exposure of the SkyBox light probe while the cube rotates. 1.0 leaves the
// panorama (or the video clip, which uses the same environment) untouched
// (DimWhileRotating off, or the cube still), otherwise the veil opacity is
// subtracted so a 360 background darkens as much as the 2D hull does. A SkyBox
// is painted by the 3D environment, so the black Rectangle that dims
// color/gradient/flat image or flat video cannot reach it; probeExposure (the
// brightness of the environment) can. The result stays in 0..1.
function skyBoxExposure(enabled, rotating, amount) {
    if (enabled !== true || rotating !== true) {
        return 1;
    }
    return Math.max(0, 1 - dimOpacity(enabled, amount));
}

// Position of the second gradient stop in 0..1 (BackgroundGradientStop is a
// 0..100 Int). KConfigXT clamps the entry, but a hand-edited kwinrc can still
// carry anything, and a non-numeric value would poison the stop with NaN, so a
// non-finite value uses the schema default (50 %) and the rest is clamped.
function gradientStopPosition(value) {
    let percent = finiteOr(value);
    if (percent === null) {
        percent = DEFAULT_GRADIENT_STOP;
    }
    return Math.min(1, Math.max(0, percent / 100));
}

// Angle in degrees applied to the gradient layer (ADR-017). Fixed (and any
// value a hand-edited kwinrc may carry) resolves to 0 so the default look is
// never distorted; FollowCube copies the cube/camera yaw and FollowCubeInverse
// mirrors it. A non-finite yaw also falls back to 0 instead of poisoning the
// transform with NaN.
function gradientRotationAngle(mode, yawDegrees) {
    if (mode !== BackgroundGradientRotation.FollowCube && mode !== BackgroundGradientRotation.FollowCubeInverse) {
        return 0;
    }
    const yaw = Number(yawDegrees);
    if (!isFiniteNumber(yaw)) {
        return 0;
    }
    return mode === BackgroundGradientRotation.FollowCube ? yaw : -yaw;
}

// Visible span of a w x h area along the gradient axis once the layer is turned
// by angleDeg (ADR-017): the projection that shows how much of the oversized
// rectangle stays on screen. Horizontal gradients measure X (|w*cos| + |h*sin|),
// vertical ones measure Y (|w*sin| + |h*cos|). A non-finite input falls back to
// 0 instead of poisoning the stops with NaN.
function gradientVisibleSpan(w, h, angleDeg, horizontal) {
    const width = Number(w);
    const height = Number(h);
    const radians = Number(angleDeg) * Math.PI / 180;
    if (!isFiniteNumber(width) || !isFiniteNumber(height) || !isFiniteNumber(radians)) {
        return 0;
    }
    const cosine = Math.abs(Math.cos(radians));
    const sine = Math.abs(Math.sin(radians));
    return horizontal ? width * cosine + height * sine : width * sine + height * cosine;
}

// Half of the unpainted margin left on each side of the visible band (0..0.5).
// The layer is the screen diagonal, so the visible span covers only part of it;
// the stops are remapped into [margin, 1 - margin] to keep Fixed's look. A
// degenerate area (w or h = 0) has no gradient to remap.
function gradientStopMargin(w, h, angleDeg, horizontal) {
    const width = Number(w);
    const height = Number(h);
    const radians = Number(angleDeg) * Math.PI / 180;
    if (!isFiniteNumber(width) || !isFiniteNumber(height) || !isFiniteNumber(radians)
        || width <= 0 || height <= 0) {
        return 0;
    }
    const diagonal = Math.hypot(width, height);
    const span = gradientVisibleSpan(width, height, angleDeg, horizontal);
    return 0.5 - 0.5 * Math.min(1, span / diagonal);
}

// True when the gradient layer follows the cube (ADR-017). Fixed and any value
// a hand-edited kwinrc may carry keep the radial focal point at the centre.
function gradientFollows(mode) {
    return mode === BackgroundGradientRotation.FollowCube || mode === BackgroundGradientRotation.FollowCubeInverse;
}

// Face opacity defaults from config/main.xml (ADR-021). The floor is 0.1,
// not 0: a fully invisible face cannot be picked or clicked, and the cube
// would become a ghost.
const DEFAULT_FACE_OPACITY = 1;
const DEFAULT_FACE_ROTATION_OPACITY = 0.7;
const MIN_FACE_OPACITY = 0.1;

// Opacity of every cube face (ADR-021). At rest FaceOpacity, while rotating
// FaceRotationOpacity (the same "moving" signal as the hull dim: drag or the
// rotation animation, never the wheel zoom). Applied to the face material,
// not the geometry, so the future cylinder mesh inherits it unchanged. A
// null/empty/non-finite value uses the schema default; 0 is a real value and
// still clamps up to the 0.1 floor. The result stays in [0.1, 1].
function faceOpacity(restOpacity, rotationOpacity, rotating) {
    // A null/empty stored value means "never configured", not 0 (the floor):
    // finiteOr maps it to the default of the active branch (ADR-022).
    let value = finiteOr(rotating === true ? rotationOpacity : restOpacity);
    if (value === null) {
        value = rotating === true ? DEFAULT_FACE_ROTATION_OPACITY : DEFAULT_FACE_OPACITY;
    }
    return Math.min(1, Math.max(MIN_FACE_OPACITY, value));
}

// Duration of the rest<->rotation opacity fade (FaceFadeMs, 0..1000 ms).
// 0 is a hard cut; a non-finite value uses the schema default (120 ms).
function faceFadeDuration(value) {
    let ms = finiteOr(value);
    if (ms === null) {
        ms = 120;
    }
    return Math.min(1000, Math.max(0, ms));
}

// Sheet geometry (ADR-024): with 1-2 desktops the solid is a sheet of
// coplanar quads, not a polygon. One desktop has no real back side (with
// Material.NoCulling the reverse shows MIRRORED content), so its azimuth is
// clamped to +/- this many degrees. Fixed on purpose: no config key until the
// user asks for one.
const SHEET_AZIMUTH_LIMIT_DEG = 80;

// Azimuth limit for the sheet: 1 desktop -> +/-80 deg (the mirrored back must
// never face the camera); anything else -> 360, which means "no limit": with 2
// desktops both sides are real desktops, and >=3 is the polygon (free wrap).
// 360 (not Infinity) so every caller compares against the same unit.
function sheetAzimuthLimit(count) {
    return count === 1 ? SHEET_AZIMUTH_LIMIT_DEG : 360;
}

// Sheet yaw in (-180, 180]: unlike the polygon there is no wrap to keep, so
// callers normalize BEFORE clamping. Non-finite input is 0 (front view).
function normalizeSheetAzimuth(azimuth) {
    const angle = Number(azimuth);
    if (!isFiniteNumber(angle)) {
        return 0;
    }
    let norm = angle % 360;
    if (norm > 180) {
        norm -= 360;
    } else if (norm <= -180) {
        norm += 360;
    }
    return norm;
}

// The azimuth clamp for the paths that SET a target angle (arrows, states),
// as an explicit [min, max] range (ADR-025; it replaces the symmetric
// clampSheetAzimuth and stays generic enough for asymmetric bounds even
// though today's only real range, the sheet's, is symmetric — the segment
// band it was built for is retired). A null/garbage bound returns the angle
// verbatim: sheet-2, the drum, the three-slot drum and the polygon turn
// freely, and verbatim is exactly what the pre-sheet code did
// — normalizing here would flip e.g. 288 to -72, an equivalent orientation
// but opposite-sign quaternions whose Behavior slerp could take the long
// way. A real range first normalizes to (-180,180] (no wrap exists on a
// limited band) and then clamps. Non-finite azimuth is the front view (0).
// The DRAG path in CubeCameraController does NOT use this helper: it
// clamps the raw delta sum between min and max without normalizing, so a
// hard pull cannot cross the band and teleport the view.
function clampAzimuthRange(azimuth, min, max) {
    const angle = Number(azimuth);
    if (!isFiniteNumber(angle)) {
        return 0;
    }
    // null/undefined BEFORE Number(): Number(null) is 0 — a finite number —
    // so coercing first would turn the open range into the degenerate [0, 0]
    // and park the view at azimuth 0 instead of letting it pass (the ADR-022
    // lesson, applied to the bounds).
    if (min === null || min === undefined || max === null || max === undefined) {
        return angle;
    }
    const lo = Number(min);
    const hi = Number(max);
    if (!isFiniteNumber(lo) || !isFiniteNumber(hi)) {
        return angle;
    }
    const norm = normalizeSheetAzimuth(angle);
    return Math.min(hi, Math.max(lo, norm));
}

// Which face of the sheet looks at the camera for a given azimuth: 0 = front,
// 1 = back (only with 2 desktops; past +/-90 deg the back quad faces the
// viewer). -1 = no sheet (>=3 desktops, 0 mid-sync) or a non-finite azimuth —
// callers map -1 to a null desktop instead of guessing a face.
function sheetDesktopAt(azimuth, count) {
    if (count !== 1 && count !== 2) {
        return -1;
    }
    const angle = Number(azimuth);
    if (!isFiniteNumber(angle)) {
        return -1;
    }
    if (count === 1) {
        return 0;
    }
    return Math.abs(normalizeSheetAzimuth(angle)) <= 90 ? 0 : 1;
}

// ---------------------------------------------------------------------------
// Cylinder shape (Shape == Cylinder, ADR-002/ADR-025). Everything here is
// pure so scripts/check-cylinder.py can build and validate the REAL arc mesh
// offscreen, without KWin or a window.
//
// A cylinder is developable (Gaussian curvature K = 0): a flat face wraps
// onto it isometrically, so the arc MUST measure exactly the face width W —
// theta = W/R is a consequence, never a free knob. That also forbids
// overlapping faces: CubeFaceDisplacement on the cylinder IS the linear gap
// g measured on the surface between neighbouring arcs, so negative values
// (polygon: faces slide over each other) clamp to 0 here.
// ---------------------------------------------------------------------------

// Fixed segment count per arc (ADR-002 allowed 32-64; 64 for large arcs /
// close-up zoom). (segments + 1) columns x 2 rows = 130 vertices per arc.
// The mesh is rebuilt only when (W, H, R) change — never per frame: the
// bindings in CylinderArcMesh.qml only re-run on those inputs, and turning
// or zooming are transformations of the Model, not of the vertices.
const CYLINDER_SEGMENTS = 64;

// Circumradius of the closed N-arc cylinder: R = N * (W + g) / (2*PI) with
// g = max(0, gap). Consecutive arcs then sit 360/N degrees apart — the SAME
// azimuths the polygon uses, so desktopAt/desktopAzimuth/angleTick are
// shape-independent — and the empty wedge between two arcs measures exactly
// g px along the surface: R * (2*PI/N - W/R) = (W + g) - W = g. With g = 0
// the arcs touch (closed cylinder, still NO skin between them: ADR-003).
// Non-finite or meaningless inputs answer 0 (the caller's safeViewRadius
// pins the camera above it); an unset/garbage gap reads as 0 through
// finiteOr, the ADR-022 rule for null/""/whitespace.
function cylinderRadius(count, faceWidth, gap) {
    const faces = Number(count);
    const width = Number(faceWidth);
    if (!isFiniteNumber(faces) || !isFiniteNumber(width) || faces < 1 || width <= 0) {
        return 0;
    }
    const value = finiteOr(gap);
    const effectiveGap = value === null ? 0 : Math.max(0, value);
    return faces * (width + effectiveGap) / (2 * Math.PI);
}

// Central angle of one arc in RADIANS: theta = W / R (isometry: the arc
// length R*theta equals W by construction). Degenerate radius (0 or garbage)
// answers 0; callers treat 0 as "no arc".
function cylinderArcAngle(faceWidth, radius) {
    const width = Number(faceWidth);
    const r = Number(radius);
    if (!isFiniteNumber(width) || !isFiniteNumber(r) || r <= 0) {
        return 0;
    }
    return width / r;
}

// One or two faces cannot CLOSE a drum on their own — but with Shape ==
// Cylinder they no longer fall back to the flat sheet nor to a capped
// "curved segment band": the solid is a THREE-SLOT drum (ADR-025 pt.11,
// re-rectified by the user after testing the [-60,60]/[-60,180] band — it
// "made jumps and felt choppy"). The drum formula simply runs with N = 3:
//
//   R    = 3 (W + g) / (2 PI)   (cylinderRadius(3, W, g) — the user's gap g
//                               APPLIES at 1-2 faces too, no fixed 3W/2pi)
//   tick = 360 / 3 = 120        (faces occupy slots 0..count-1, azimuths
//                               0 and 120; the azimuth helper is gone:
//                               Cube.angleTick * index answers it)
//   slots without a desktop are NOT created: the hull shows through there,
//   an "empty face" without a panel (ADR-003 parity).
//
// The turn range is OPEN at every cylinder count (like the drum): free
// wrap, no band clamps, no asymmetric edges — and the mirrored back of the
// far arcs seen through the gaps is tolerated exactly as the real drum
// tolerates it (ADR-023). desktopAt/desktopAzimuth need no special cases:
// Cube's standard tick-grid arithmetic modulo the slot count lands on a
// missing delegate for empty slots, which Cube already maps to a null
// desktop (a no-op selection; a DRAG can park facing the hull there). The
// ARROWS are the exception (ADR-026b): with 1-2 desktops the grid has a
// hole, so arrowAzimuth walks the real face list instead of the raw tick —
// an empty slot is never an arrow stop («no se puede pasar» as measured by
// the user).
// cylinderArcRadius / cylinderSegmentAzimuth / cylinderAzimuthRange /
// cylinderSegmentDesktopAt (the band design) are retired; the flat sheet
// (Shape == Polygon, 1-2) is untouched (ADR-024).



// The FLAT sheet's symmetric caps expressed as the same [min, max] shape,
// so the camera has ONE clamp mechanism for every limited form
// (ADR-024/ADR-025): 1 desktop -> [-80, 80] via SHEET_AZIMUTH_LIMIT_DEG,
// 2 desktops / >= 3 / garbage -> [null, null] (no limit — the polygon and
// the two-sided sheet turn freely). Behaviour-identical to the old
// azimuthLimit number: the drag clamps the raw sum the same way, and
// clampAzimuthRange(azimuth, -80, 80) equals clampSheetAzimuth(azimuth, 80).
function flatAzimuthRange(count) {
    const limit = sheetAzimuthLimit(count);
    return limit >= 360 ? [null, null] : [-limit, limit];
}

// The turn range the camera must obey, routed by shape (ADR-026, recast by
// the three-slot drum decision): ScreenView used to branch on cube flags
// inline, which no check could catch swapped. Inputs: the resolved Shape,
// the raw delegate count and whether the arc mesh exists.
//   cylinder + arc mesh (1, 2 or N — the three-slot drum wraps freely)
//                                  -> [null, null] (open, like the drum)
//   polygon / cylinder WITHOUT mesh (the flat-sheet fallback: a rectangle
//   face must not show its mirrored back) -> flatAzimuthRange: [-80,80]
//   with one desktop, open otherwise.
// Strict shape comparison (constants.shape() only ever answers the enum
// ints). The count argument only matters on the flat branch.
function azimuthRangeFor(shape, count, hasArcMesh) {
    if (shape === Shape.Cylinder && hasArcMesh === true) {
        return [null, null];
    }
    return flatAzimuthRange(count);
}

// Vertex data of ONE face-arc, generated around ITS OWN NODE: the arc's
// mid-point sits at the origin and the drum axis at (0, 0, -R), so placing
// the face is exactly the polygon rule — position = rotate(azimuth) *
// (0, 0, faceDistance=R) plus eulerRotation.y = azimuth (ADR-026). The old
// mesh lived centred on +Z with every node pinned to (0, 0, 0): all the
// faces then shared one sort centroid and QtQuick3D's transparent-pass
// ordering (world bounds centre -> view depth, qssglayerrenderdata.cpp)
// lost a reliable key for the drum; the polygon never had that problem
// because each Model already carries its own position. phi0 is NOT baked
// into the mesh, which is what lets all faces still share one geometry.
// Returns {positions, normals, uvs, indexes} in the shape ProceduralMesh
// wants (lists of Qt.vector3d / Qt.vector2d / uint), for arc-length s in
// [0, W] and height t in [0, H]:
//
//   phi(s)    = (s - W/2) / R            arc symmetric about +Z, mid at 0
//   P(s, t)   = (R sin phi, t - H/2, R cos phi - R)
//   normal(s) = (sin phi, 0, cos phi)    radial, pointing OUT of the axis
//   uv(s, t)  = (s / W, t / H)           v = 0 at the bottom row (y = -H/2)
//
// The v convention was MEASURED, not assumed: decoding Qt 6.12's own
// Rectangle.mesh shows the built-in #Rectangle carries (u, v) = (0, 0) at
// (x, y) = (-50, -50) and (1, 1) at (50, 50) — bottom-left origin — so the
// same Texture { sourceItem } that paints a polygon face upright paints the
// arc upright (winding is likewise CCW seen from outside, like the
// rectangle's own 0,1,2 order).
//
// Degenerate input (a zero/garbage width, height or radius — transiently
// possible while the model syncs) answers EMPTY arrays: a ProceduralMesh
// with no positions renders nothing, which is the safe mid-sync state.
function cylinderArcGeometry(faceWidth, faceHeight, radius, segments) {
    const width = Number(faceWidth);
    const height = Number(faceHeight);
    const r = Number(radius);
    if (!isFiniteNumber(width) || !isFiniteNumber(height) || !isFiniteNumber(r)
        || width <= 0 || height <= 0 || r <= 0) {
        return { positions: [], normals: [], uvs: [], indexes: [] };
    }
    const rawSegments = Number(segments);
    const segs = isFiniteNumber(rawSegments) ? Math.max(1, Math.floor(rawSegments)) : CYLINDER_SEGMENTS;

    const positions = [];
    const normals = [];
    const uvs = [];
    const indexes = [];

    for (let i = 0; i <= segs; ++i) {
        // Column i sits at arc-length s = W*i/segs, centred: phi runs from
        // -theta/2 to +theta/2 with theta = W/R.
        const phi = (width * i / segs - width / 2) / r;
        const sine = Math.sin(phi);
        const cosine = Math.cos(phi);
        // Two vertices per column: bottom (v = 0) then top (v = 1), so the
        // indexes of a column are (2i, 2i + 1).
        positions.push(Qt.vector3d(r * sine, -height / 2, r * cosine - r),
                       Qt.vector3d(r * sine, height / 2, r * cosine - r));
        normals.push(Qt.vector3d(sine, 0, cosine), Qt.vector3d(sine, 0, cosine));
        uvs.push(Qt.vector2d(i / segs, 0), Qt.vector2d(i / segs, 1));
    }

    for (let i = 0; i < segs; ++i) {
        const a = 2 * i; //     bottom, column i
        const b = a + 1; //     top,    column i
        const c = a + 2; //     bottom, column i + 1
        const d = a + 3; //     top,    column i + 1
        // Cross products of both triangles point along the radial (outward)
        // normal: seen from OUTSIDE the cylinder each triangle runs
        // counter-clockwise, the same convention as #Rectangle's mesh.
        indexes.push(a, c, b, b, c, d);
    }

    return { positions: positions, normals: normals, uvs: uvs, indexes: indexes };
}

// Cull tokens (ADR-025 point 12): 1 = cull back faces (only the arcs' outer
// skin is visible), 0 = cull nothing. NO LONGER APPLIED AT RUNTIME: the
// dynamic BackFaceCulling outside 1.05 R was reverted by the user — seeing
// the mirrored inner wall of the far arcs through the gaps is polygon
// parity (ADR-023); the real complaint was inner faces being PAINTED OVER
// the front ones, which is a paint-order/depth problem, not a culling one
// (Cube.faceCullMode is pinned to NoCulling, so cylinderCullMode stays a
// proven-unused seed: the pointer a re-enable of point 12 would start from).
// The helper and its tests stay as the documented seed of that fix, and as
// a diagnostic switch. The raw ints of Qt's CullMode enum must NEVER be
// hardcoded here: in Qt 6.12.1 they are BackFaceCulling = 1,
// FrontFaceCulling = 2, NoCulling = 3 (measured in the installed private
// header) — a fixed 2 would mean FrontFaceCulling, the opposite effect.
//
// Rule: outside the drum — camera radius > R * 1.05 (the 5 % margin is the
// anti-flicker hysteresis around the threshold while the zoom animates) —
// back faces are culled: the mirrored inner wall of the far arcs used to
// cover the front faces through and above the gaps (measured with
// DebugOverlay, f1:-0.99/f2:-1.00). Inside R (the deep zoom the wheel
// allows: minRadius is 0.6·R) culling stays off, so the drum never becomes
// an empty ghost shell viewed from within.
//
// Unusable input (NaN, camera at 0 = never bound, radius <= 0 = the
// degenerate mesh) answers 0: the safe old rendering, never a surprise
// cull. Nothing in the runtime calls this since the pt.12 revert — the
// polygon and the sheet keep NoCulling always (ADR-023, the virgin look the
// user defended) and the cylinder now matches them; the wiring check drives
// it explicitly to keep the contract of the seed alive.
function cylinderCullMode(cameraRadius, radius) {
    const cam = Number(cameraRadius);
    const r = Number(radius);
    if (!isFiniteNumber(cam) || !isFiniteNumber(r) || cam <= 0 || r <= 0) {
        return 0;
    }
    return cam > r * 1.05 ? 1 : 0;
}

// The azimuth the ARROW buttons should rotate to (ADR-025 point 13): on a
// LIMITED range the next REAL FACE in the requested direction, not a raw
// tick multiple clamped afterwards — the trace that motivated it ran on the
// segment band [-60, 180] (faces at 0 and 120): LEFT from 0 hit -120 ->
// clamped to the -60 edge (hull only), then delta 0 forever — desktop 2
// unreachable — and RIGHT from 120 hit 240 -> normalized -120 -> clamped
// -60, a -180 turn backwards. That band is RETIRED (three-slot drum design,
// ADR-025 pt.11 re-rectified): today's only limited range is the symmetric
// sheet-1 [-80, 80]. A cylinder with the arc mesh turns freely on the slot
// grid — and with 1-2 desktops that grid has an EMPTY slot the raw tick walk
// would park the camera on (Enter there is the guarded no-op — «no se puede
// pasar», measured with the user's DebugOverlay at yaw=-103.9, parked). The
// ADR-026b rule for the OPEN range: real faces that do NOT fill the grid
// (faces.length < 360/tick — in practice exactly the three-slot drum at 1-2
// desktops) make the arrow advance to the next REAL face in the requested
// direction, wrapping the full circle and rotating the shortest way to it
// (n=2: 0 <-> 120 from either side, never 240; n=1: no-op; an off-grid start
// from a drag lands on the closest real face). Faces that DO fill the grid
// (drum at 3+, polygon, two-sided sheet, and the empty transient of a
// mid-sync model — with no faces to cycle the grid step must not freeze)
// keep the pre-cylinder arithmetic verbatim, byte for byte (ADR-022/024
// parity).
//
//   direction +1 = right (Keys.onRightPressed), -1 = left;
//   tick         = cube.angleTick;
//   min/max      = the live turn range (root.azimuthRange), null = open;
//   faceAzimuths = the REAL face azimuths (Cube.faceAzimuth(i) per face —
//                  the same function the delegate places the faces with).
//
// Open range, full grid: the pre-cylinder arithmetic verbatim — snap to the
// tick grid (floor/ceil), advance one tick when already on it (the 0.05 tick
// threshold), return the result WITHOUT normalizing (450 stays 450: the
// equivalent-but-opposite-sign quaternion would let the Behavior slerp the
// long way; the old clampAzimuthRange verbatim rule, kept as-is so polygon,
// drum and two-sided sheet behave EXACTLY like before).
//
// Limited range: pick from the face list, in normalized (-180, 180] space.
// If the current azimuth stands on a face (within the 0.05 tick threshold)
// that face is skipped; the result is then the highest face below the
// current for left / the lowest face above it for right; with no face in
// that direction the band wraps — left goes to the highest face, right to
// the lowest (a carousel of the faces that exist, never the empty edge of
// the range). With one face (sheet-1 [-80, 80] — today's only real limited
// range since the segment band was retired) the wrap answers the same
// face: delta 0, the arrow holds — the same
// final position the old normalize+clamp produced for sheet-1 (360 -> 0),
// now stated and tested instead of emergent.
//
// Garbage: a non-finite current answers 0 (the front view, the same guard
// clampAzimuthRange uses); a broken tick with an open range answers the
// current; an empty/non-array face list falls back to the open arithmetic
// (with a range) or the current (limited range without faces = no-op —
// safer than pointing at azimuths with no desktop).
function arrowAzimuth(currentAzimuth, direction, tick, azimuthMin, azimuthMax, faceAzimuths) {
    const current = Number(currentAzimuth);
    if (!isFiniteNumber(current)) {
        return 0;
    }
    const step = Number(direction) < 0 ? -1 : 1;
    const faces = Array.isArray(faceAzimuths) ? faceAzimuths : [];
    const lo = Number(azimuthMin);
    const hi = Number(azimuthMax);
    const limited = azimuthMin !== null && azimuthMin !== undefined && isFiniteNumber(lo)
                    && azimuthMax !== null && azimuthMax !== undefined && isFiniteNumber(hi);
    const t = Number(tick);

    if (limited) {
        if (faces.length === 0) {
            return current;
        }
        const threshold = (isFiniteNumber(t) && t > 0 ? t : 360) * 0.05;
        const norm = normalizeSheetAzimuth(current);
        // Skip the face the camera stands on (if any).
        let ahead = null;
        let best = null;
        for (const item of faces) {
            const face = Number(item);
            if (!isFiniteNumber(face)) {
                continue;
            }
            const offset = normalizeSheetAzimuth(norm - face);
            if (Math.abs(offset) < threshold) {
                ahead = face;
                break;
            }
        }
        for (const item of faces) {
            const face = Number(item);
            if (!isFiniteNumber(face) || (ahead !== null && face === ahead)) {
                continue;
            }
            if (step > 0 ? face > norm : face < norm) {
                if (best === null || (step > 0 ? face < best : face > best)) {
                    best = face;
                }
            }
        }
        if (best !== null) {
            return best;
        }
        // Wrap inside the band: highest face for left, lowest for right.
        for (const item of faces) {
            const face = Number(item);
            if (!isFiniteNumber(face)) {
                continue;
            }
            if (best === null || (step > 0 ? face < best : face > best)) {
                best = face;
            }
        }
        return best === null ? current : best;
    }

    if (!isFiniteNumber(t) || t <= 0) {
        return current;
    }

    // Open range with holes in the tick grid (ADR-026b, the three-slot drum
    // at 1-2 desktops: tick 120, faces [0] or [0, 120], slot 2 empty): walk
    // the REAL faces circularly instead of the raw grid, so no arrow stop
    // ever lands the camera on an empty slot. The standing face is skipped
    // with the STRICT < against the 0.05 tick threshold — the same
    // convention as the limited branch and the verbatim grid path below
    // (exactly 0.05*tick away counts as NOT standing: the arrow snaps to
    // the face; tested at the boundary). Ahead in the requested direction
    // wins, otherwise the sweep wraps the circle (the face that is furthest
    // BEHIND is the first one past +-180). A single real face already stood
    // on: no other stop, return the current verbatim, the arrow holds (n=1
    // drum). The answer is the chosen face's representative nearest to the
    // current angle, so the quaternion Behavior always slerps the short way
    // (same verbatim-sign rule as the grid path below).
    const slots = Math.round(360 / t);
    if (slots > 1 && faces.length > 0 && faces.length < slots) {
        const threshold = t * 0.05;
        const centre = normalizeSheetAzimuth(current);
        let ahead = null;
        let wrap = null;
        for (const item of faces) {
            const face = Number(item);
            if (!isFiniteNumber(face)) {
                continue;
            }
            const offset = normalizeSheetAzimuth(face - centre);
            if (Math.abs(offset) < threshold) {
                continue;
            }
            if (step > 0 ? offset > 0 : offset < 0) {
                if (ahead === null || Math.abs(offset) < Math.abs(ahead)) {
                    ahead = offset;
                }
            } else if (wrap === null || Math.abs(offset) > Math.abs(wrap)) {
                wrap = offset;
            }
        }
        // Plain Number.isFinite on purpose, NOT isFiniteNumber(): ahead/wrap are
        // null sentinels and Number.isFinite(null) is false, so the fallback
        // chain and the offset === null guard below keep their meaning. With
        // isFiniteNumber() the null would pass as 0 and the arrow would stop
        // holding on a one-face band.
        const offset = Number.isFinite(ahead) ? ahead : wrap;
        if (offset === null) {
            return current;
        }
        const stop = centre + offset;
        return stop + 360 * Math.round((current - stop) / 360);
    }

    let next = step > 0 ? Math.ceil(current / t) * t : Math.floor(current / t) * t;
    if (Math.abs(next - current) < 0.05 * t) {
        next += step * t;
    }
    return next;
}

// KConfig hands a Url entry as a url value (not a string), and the entry can
// be undefined/null before the KCM saves anything. Only local resources are
// accepted: the compositor must not fetch remote content when the effect
// activates, and QtQuick3D could not use a remote texture anyway.
function backgroundImageSource(value) {
    return localSource(value, ["file", "image"]);
}

// Same rules for the video (Background == Video), but narrower: a clip must be
// a local file. "image:" is rejected (no video provider behind it) and any
// remote scheme too, for the same reason as the image.
function videoSource(value) {
    return localSource(value, ["file"]);
}

// ---------------------------------------------------------------------------
// Caps (tapas, ADR-027): the top and bottom closing surfaces of the solid.
// Everything here is pure so scripts/check-cap.py can build and validate the
// REAL cap mesh (the same ProceduralMesh data CapMesh.qml exposes) offscreen,
// without KWin or a window — exactly like the cylinder section above.
// ---------------------------------------------------------------------------

// Matches the CapContent enum in config/main.xml.
const CapContent = {
    Color: 0,
    Gradient: 1,
    Image: 2
};
// Matches the CapGradientType enum in config/main.xml. Same order as
// BackgroundGradientType by design (the cap paints through HullGradient), but
// it is its OWN table because check-schema.py mirrors EVERY Enum entry of
// main.xml to a constants.js table of the entry's name.
const CapGradientType = {
    LinearVertical: 0,
    LinearHorizontal: 1,
    Radial: 2
};
// Matches the CapImageFit enum in config/main.xml (same order as
// BackgroundImageFit; own table for the same check-schema reason).
const CapImageFit = {
    Cover: 0,
    Contain: 1,
    Stretch: 2
};
// Defaults from config/main.xml, used when the stored value is not usable
// (the backgroundMode / imageFit / gradientStop fallback pattern).
const DEFAULT_CAP_CONTENT = CapContent.Color;
const DEFAULT_CAP_GRADIENT_TYPE = CapGradientType.LinearVertical;
const DEFAULT_CAP_IMAGE_FIT = CapImageFit.Cover;
const DEFAULT_CAP_OPACITY = 80;

// CapOpacity is an Int 0..100 (ADR-027 chose it over a Double for parity
// with DimWhileRotatingAmount); the material needs 0..1. An unset or
// non-finite value uses the schema default (80 %), the rest clamps — the
// dimOpacity contract, minus the enabled flag (visibility is CapTop/CapBottom,
// not the amount, so 0 here is a real transparent cap and must stay 0).
function capOpacity(value) {
    let percent = finiteOr(value);
    if (percent === null) {
        percent = DEFAULT_CAP_OPACITY;
    }
    return Math.min(1, Math.max(0, percent / 100));
}

// Unknown CapContent values (a hand-edited kwinrc) fall back to the solid
// colour — the safest thing a cap can paint.
function capContent(value) {
    if (value === CapContent.Gradient || value === CapContent.Image) {
        return value;
    }
    return DEFAULT_CAP_CONTENT;
}

// Same rule for the gradient type: an unknown value is the linear vertical
// of the schema default, never a broken index.
function capGradientType(value) {
    if (value === CapGradientType.LinearHorizontal || value === CapGradientType.Radial) {
        return value;
    }
    return DEFAULT_CAP_GRADIENT_TYPE;
}

// And the image fit: unknown is Cover, the schema default (imageFit pattern).
function capImageFit(value) {
    if (value === CapImageFit.Contain || value === CapImageFit.Stretch) {
        return value;
    }
    return DEFAULT_CAP_IMAGE_FIT;
}

// Cap image: local resources only, the SAME filter as the background image
// (file: or image:, bare paths kept; the compositor must not fetch anything
// when the effect activates — 2.2 of doc/requerimientos.md).
function capImageSource(value) {
    return localSource(value, ["file", "image"]);
}

// Regular N-gon in the XZ plane (y = 0) with the APOTEM equal to `apothem`,
// centred on the node origin: the caps close the solid at y = +/- halfHeight,
// but that offset is the NODE's position (Cube places the top/bottom Models
// there), so one flat mesh serves both caps — the bottom one comes from a
// 180 deg node rotation, never from a second geometry (ADR-027). The
// circumradius is DERIVED (apothem / cos(pi/n)): faceDistance stays the only
// geometric source of truth, the cap cannot ever poke out of the walls.
//
//   n        = sides (>= 3; the polygon floor, geometryCount = max(3, faces))
//   rc       = apothem / cos(pi / n)
//   alpha(k) = 2*pi * (k + 0.5) / n   -> the EDGE midpoints land on azimuths
//              k * 2*pi/n, exactly where Cube.faceAzimuth places the faces,
//              so every edge lies on its face's plane (inscribed cap).
//   vertex k = (rc sin alpha_k, 0, rc cos alpha_k)
//   normal   = (0, 1, 0)               CCW seen from +Y = the top cap's
//                                      outward side; the bottom cap flips it
//                                      through its node rotation.
//   uv       = (0.5 + x/(2 rc), 0.5 + z/(2 rc))   centred, always in [0,1]
//
// Degenerate input answers EMPTY arrays (the cylinderArcGeometry contract):
// apothem <= 0 happens for transient states and for a hand-edited negative
// displacement beyond the apothem (ADR-022 range), sides < 3 is not a
// polygon, and a non-finite halfHeight means faceSize has not settled yet —
// a half-height the node position must respect, so mid-sync renders nothing
// instead of a floating NaN plane.
function capPolygonGeometry(apothem, sides, halfHeight) {
    const a = Number(apothem);
    const rawSides = Number(sides);
    const h = Number(halfHeight);
    if (!isFiniteNumber(a) || a <= 0 || !isFiniteNumber(h) || h <= 0
        || !isFiniteNumber(rawSides) || Math.floor(rawSides) < 3) {
        return { positions: [], normals: [], uvs: [], indexes: [] };
    }
    const n = Math.floor(rawSides);
    // n >= 3 keeps cos(pi/n) >= 0.5: the circumradius is finite and positive.
    const rc = a / Math.cos(Math.PI / n);
    const step = 2 * Math.PI / n;

    const positions = [];
    const normals = [];
    const uvs = [];
    const indexes = [];

    // Vertex 0 is the centre; the ring runs 1..n so the fan triangles are
    // (0, 1 + k, 1 + (k + 1) mod n) — CCW seen from +Y (cross(e1, e2) along
    // +Y for increasing azimuth, same outward convention as the arc mesh).
    positions.push(Qt.vector3d(0, 0, 0));
    normals.push(Qt.vector3d(0, 1, 0));
    uvs.push(Qt.vector2d(0.5, 0.5));
    for (let k = 0; k < n; ++k) {
        const alpha = step * (k + 0.5);
        const x = rc * Math.sin(alpha);
        const z = rc * Math.cos(alpha);
        positions.push(Qt.vector3d(x, 0, z));
        normals.push(Qt.vector3d(0, 1, 0));
        uvs.push(Qt.vector2d(0.5 + x / (2 * rc), 0.5 + z / (2 * rc)));
    }
    for (let k = 0; k < n; ++k) {
        indexes.push(0, 1 + k, 1 + ((k + 1) % n));
    }

    return { positions: positions, normals: normals, uvs: uvs, indexes: indexes };
}

// Disc of radius `radius` in the XZ plane (y = 0), fan-triangulated from the
// centre: the cap of the cylinder at any count, drum or three-slot drum
// (ADR-027: it closes the empty wedges too). Same conventions as
// capPolygonGeometry — derived nothing (R is already the single source),
// normals +Y, CCW seen from +Y, centred UVs, one flat mesh shared by both
// caps through a node rotation. `segments` follows the arc mesh (64, fixed),
// so the disc silhouette matches the drum it closes. Degenerate input
// (radius <= 0, non-finite halfHeight, fewer than 3 segments) answers EMPTY
// arrays, exactly like the arc generator's mid-sync rule.
function capDiscGeometry(radius, segments, halfHeight) {
    const r = Number(radius);
    const rawSegments = Number(segments);
    const h = Number(halfHeight);
    if (!isFiniteNumber(r) || r <= 0 || !isFiniteNumber(h) || h <= 0
        || !isFiniteNumber(rawSegments) || Math.floor(rawSegments) < 3) {
        return { positions: [], normals: [], uvs: [], indexes: [] };
    }
    const s = Math.floor(rawSegments);
    const step = 2 * Math.PI / s;

    const positions = [];
    const normals = [];
    const uvs = [];
    const indexes = [];

    positions.push(Qt.vector3d(0, 0, 0));
    normals.push(Qt.vector3d(0, 1, 0));
    uvs.push(Qt.vector2d(0.5, 0.5));
    for (let k = 0; k < s; ++k) {
        // No half-step offset: a disc is rotationally symmetric, its ring
        // needs no alignment with the face azimuths (unlike the polygon).
        const x = r * Math.sin(step * k);
        const z = r * Math.cos(step * k);
        positions.push(Qt.vector3d(x, 0, z));
        normals.push(Qt.vector3d(0, 1, 0));
        uvs.push(Qt.vector2d(0.5 + x / (2 * r), 0.5 + z / (2 * r)));
    }
    for (let k = 0; k < s; ++k) {
        indexes.push(0, 1 + k, 1 + ((k + 1) % s));
    }

    return { positions: positions, normals: normals, uvs: uvs, indexes: indexes };
}

// Shared scheme filter of backgroundImageSource/videoSource/capImageSource. A
// bare path (no scheme) is kept only when it is absolute: a relative one would
// be resolved against the compositor working directory, which is not something
// the effect defines, and it can carry traversal segments. The traversal check
// is defence in depth against a hand-edited kwinrc, NOT a security boundary:
// whoever writes [Effect-kube-effect] already controls the session, and an
// absolute path to any readable file is still accepted (the pickers write
// exactly that). The documented KDE providers keep working because "image://"
// is a listed scheme: its authority ("wallpaper") is not a filesystem segment,
// so a plain path-segment test is what fits here, not a normalized realpath.
function localSource(value, schemes) {
    if (value === undefined || value === null) {
        return "";
    }
    const source = String(value);
    if (source.length === 0) {
        return "";
    }
    const scheme = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(source);
    if (scheme !== null && !schemes.includes(scheme[1])) {
        return "";
    }
    if (/(^|[\/])\.\.([\/]|$)/.test(source)) {
        return "";
    }
    if (scheme === null && !source.startsWith("/")) {
        return "";
    }
    return source;
}
