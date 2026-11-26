import QtQuick
import "../package/contents/ui/constants.js" as Constants

// Runs inside scripts/check-constants.py. The holder `h` exposes QUrl
// properties, i.e. exactly what KConfigLoader hands QML for a Url entry: the
// conversions below are the ones the effect sees in KWin.
Item {
    id: root

    property bool ok: true
    property string log: ""

    function check(name, actual, expected) {
        const passed = actual === expected;
        const line = (passed ? "PASS " : "FAIL ") + name + " = " + actual + (passed ? "" : " (expected " + expected + ")");
        log = log.length > 0 ? log + "\n" + line : line;
        if (!passed)
            ok = false;
    }

    // Projected spans are trigonometric, so 180/360 only match 0 within float
    // noise (sin(pi) is not exactly 0); the identity checks stay exact.
    function checkClose(name, actual, expected, epsilon) {
        const tolerance = epsilon === undefined ? 1e-9 : epsilon;
        const passed = Math.abs(actual - expected) <= tolerance;
        const line = (passed ? "PASS " : "FAIL ") + name + " = " + actual + (passed ? "" : " (expected ~" + expected + ")");
        log = log.length > 0 ? log + "\n" + line : line;
        if (!passed)
            ok = false;
    }

    Component.onCompleted: {
        // Background mode: an unknown value (hand-edited kwinrc) must still
        // paint a hull instead of leaving the scene transparent.
        check("mode(Color)", Constants.backgroundMode(Constants.Background.Color), Constants.Background.Color);
        check("mode(Image)", Constants.backgroundMode(Constants.Background.Image), Constants.Background.Image);
        check("mode(Gradient)", Constants.backgroundMode(Constants.Background.Gradient), Constants.Background.Gradient);
        check("mode(Video)", Constants.backgroundMode(Constants.Background.Video), Constants.Background.Video);
        check("mode(unknown int)", Constants.backgroundMode(4), Constants.Background.Color);
        check("mode(-1)", Constants.backgroundMode(-1), Constants.Background.Color);
        check("mode(undefined)", Constants.backgroundMode(undefined), Constants.Background.Color);
        check("mode(null)", Constants.backgroundMode(null), Constants.Background.Color);
        check("mode(string)", Constants.backgroundMode("2"), Constants.Background.Color);

        // Debug overlay name (ADR-023): every enum value maps to its main.xml
        // choice name; anything else says so instead of printing "undefined".
        check("name(Color)", Constants.backgroundName(Constants.Background.Color), "Color");
        check("name(Image)", Constants.backgroundName(Constants.Background.Image), "Image");
        check("name(Gradient)", Constants.backgroundName(Constants.Background.Gradient), "Gradient");
        check("name(Video)", Constants.backgroundName(Constants.Background.Video), "Video");
        check("name(unknown int)", Constants.backgroundName(9), "Unknown");
        check("name(undefined)", Constants.backgroundName(undefined), "Unknown");
        check("name(null)", Constants.backgroundName(null), "Unknown");
        check("name(string)", Constants.backgroundName("Video"), "Unknown");

        // Image layout: Equirect is the default, only an explicit Flat turns it
        // off. Unknown values (hand-edited BackgroundImageLayout) must resolve
        // to equirect instead of silently flattening a panorama; values under
        // the old BackgroundImageMapping key never arrive (orphaned in kwinrc).
        check("equirect(Equirect, no image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Equirect, false), true);
        check("equirect(Equirect, image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Equirect, true), true);
        check("equirect(Flat, image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Flat, true), false);
        check("equirect(Flat, no image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Flat, false), false);
        check("equirect(unknown 2, image)", Constants.usesEquirectMapping(2, true), true);
        check("equirect(unknown 2, no image)", Constants.usesEquirectMapping(2, false), true);
        check("equirect(unknown 7, image)", Constants.usesEquirectMapping(7, true), true);
        check("equirect(undefined, image)", Constants.usesEquirectMapping(undefined, true), true);
        check("equirect(undefined, no image)", Constants.usesEquirectMapping(undefined, false), true);
        check("equirect(null, image)", Constants.usesEquirectMapping(null, true), true);
        check("equirect(string, image)", Constants.usesEquirectMapping("1", true), true);

        // Flat-image fit: only Contain/Stretch are accepted; anything else
        // (legacy or hand-edited) is Cover, the schema default.
        check("fit(Cover)", Constants.imageFit(Constants.BackgroundImageFit.Cover), Constants.BackgroundImageFit.Cover);
        check("fit(Contain)", Constants.imageFit(Constants.BackgroundImageFit.Contain), Constants.BackgroundImageFit.Contain);
        check("fit(Stretch)", Constants.imageFit(Constants.BackgroundImageFit.Stretch), Constants.BackgroundImageFit.Stretch);
        check("fit(unknown 3)", Constants.imageFit(3), Constants.BackgroundImageFit.Cover);
        check("fit(negative)", Constants.imageFit(-1), Constants.BackgroundImageFit.Cover);
        check("fit(undefined)", Constants.imageFit(undefined), Constants.BackgroundImageFit.Cover);
        check("fit(null)", Constants.imageFit(null), Constants.BackgroundImageFit.Cover);
        check("fit(string)", Constants.imageFit("contain"), Constants.BackgroundImageFit.Cover);

        // Rotating veil: off is always 0, amount is a percentage clamped to
        // 0..1, and an unusable amount uses the schema default (40 %).
        check("dim(off, 40)", Constants.dimOpacity(false, 40), 0);
        check("dim(off, 100)", Constants.dimOpacity(false, 100), 0);
        check("dim(on, 40)", Constants.dimOpacity(true, 40), 0.4);
        check("dim(on, 0)", Constants.dimOpacity(true, 0), 0);
        check("dim(on, 100)", Constants.dimOpacity(true, 100), 1);
        check("dim(on, 150)", Constants.dimOpacity(true, 150), 1);
        check("dim(on, -20)", Constants.dimOpacity(true, -20), 0);
        check("dim(on, undefined)", Constants.dimOpacity(true, undefined), 0.4);
        // Number(null)/Number("") are 0: unset amount uses the default (ADR-022).
        check("dim(on, null)", Constants.dimOpacity(true, null), 0.4);
        check("dim(on, empty)", Constants.dimOpacity(true, ""), 0.4);
        check("dim(undefined, 40)", Constants.dimOpacity(undefined, 40), 0);

        // SkyBox exposure: 1.0 when not dimming or not rotating, otherwise the
        // veil opacity is subtracted (same amount as the 2D hull), clamped at 0
        // so a hand-edited amount above 100 cannot turn the value negative.
        check("exposure(off, still)", Constants.skyBoxExposure(false, false, 40), 1);
        check("exposure(off, rotating)", Constants.skyBoxExposure(false, true, 40), 1);
        check("exposure(on, still)", Constants.skyBoxExposure(true, false, 40), 1);
        check("exposure(on, rotating, 40)", Constants.skyBoxExposure(true, true, 40), 0.6);
        check("exposure(on, rotating, 0)", Constants.skyBoxExposure(true, true, 0), 1);
        check("exposure(on, rotating, 100)", Constants.skyBoxExposure(true, true, 100), 0);
        check("exposure(on, rotating, 150)", Constants.skyBoxExposure(true, true, 150), 0);
        check("exposure(on, rotating, -20)", Constants.skyBoxExposure(true, true, -20), 1);
        check("exposure(on, rotating, undefined)", Constants.skyBoxExposure(true, true, undefined), 0.6);
        check("exposure(undefined, rotating)", Constants.skyBoxExposure(undefined, true, 40), 1);
        check("exposure(on, undefined)", Constants.skyBoxExposure(true, undefined, 40), 1);

        // Gradient stop: percentage clamped to 0..1, non-finite or empty ->
        // schema default (50 %). KConfigXT hands a typed Int, so null only
        // comes from a hand-edited value; it means "unset" (default), not 0
        // (ADR-022).
        check("stop(0)", Constants.gradientStopPosition(0), 0);
        check("stop(50)", Constants.gradientStopPosition(50), 0.5);
        check("stop(100)", Constants.gradientStopPosition(100), 1);
        check("stop(150)", Constants.gradientStopPosition(150), 1);
        check("stop(-20)", Constants.gradientStopPosition(-20), 0);
        check("stop(string)", Constants.gradientStopPosition("abc"), 0.5);
        check("stop(undefined)", Constants.gradientStopPosition(undefined), 0.5);
        check("stop(null)", Constants.gradientStopPosition(null), 0.5);
        check("stop(empty)", Constants.gradientStopPosition(""), 0.5);

        // Gradient rotation: only the gradient hull (ADR-017). Fixed is always
        // 0, FollowCube copies the yaw, FollowCubeInverse mirrors it, and an
        // unknown mode (hand-edited kwinrc) leaves the layer still.
        check("rotation(Fixed, 90)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.Fixed, 90), 0);
        check("rotation(Fixed, 0)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.Fixed, 0), 0);
        check("rotation(FollowCube, 90)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, 90), 90);
        check("rotation(FollowCube, -45)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, -45), -45);
        check("rotation(FollowCube, 0)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, 0), 0);
        check("rotation(Inverse, 90)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCubeInverse, 90), -90);
        check("rotation(Inverse, -45)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCubeInverse, -45), 45);
        check("rotation(Inverse, 0)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCubeInverse, 0), 0);
        check("rotation(unknown 9, 90)", Constants.gradientRotationAngle(9, 90), 0);
        check("rotation(undefined, 90)", Constants.gradientRotationAngle(undefined, 90), 0);
        check("rotation(FollowCube, undefined)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, undefined), 0);

        // Gradient geometry (ADR-017): the projection and the stop remap live
        // in constants.js, so HullGradient.qml keeps no copy of them. 180/360
        // equal 0 up to float noise; a zero width or height has no band.
        check("span(v, 0)", Constants.gradientVisibleSpan(800, 600, 0, false), 600);
        check("span(h, 0)", Constants.gradientVisibleSpan(800, 600, 0, true), 800);
        checkClose("span(v, 90)", Constants.gradientVisibleSpan(800, 600, 90, false), 800);
        checkClose("span(h, 90)", Constants.gradientVisibleSpan(800, 600, 90, true), 600);
        checkClose("span(v, 45)", Constants.gradientVisibleSpan(800, 600, 45, false), 1400 * Math.SQRT1_2);
        checkClose("span(v, 180) = 0deg", Constants.gradientVisibleSpan(800, 600, 180, false), 600);
        checkClose("span(v, 360) = 0deg", Constants.gradientVisibleSpan(800, 600, 360, false), 600);

        checkClose("margin(v, 0)", Constants.gradientStopMargin(800, 600, 0, false), 0.2);
        check("margin(v, 0) identity", Constants.gradientStopMargin(800, 600, 0, false), 0.5 - 0.5 * 600 / Math.hypot(800, 600));
        checkClose("margin(v, 90)", Constants.gradientStopMargin(800, 600, 90, false), 0.1);
        checkClose("margin(v, 180) = 0deg", Constants.gradientStopMargin(800, 600, 180, false), 0.2);
        checkClose("margin(v, 360) = 0deg", Constants.gradientStopMargin(800, 600, 360, false), 0.2);
        checkClose("margin(w = h)", Constants.gradientStopMargin(800, 800, 0, false), 0.5 - 0.5 * Math.SQRT1_2);
        check("margin(w = 0)", Constants.gradientStopMargin(0, 600, 45, false), 0);
        check("margin(h = 0)", Constants.gradientStopMargin(800, 0, 45, false), 0);
        check("margin(w = h = 0)", Constants.gradientStopMargin(0, 0, 45, true), 0);

        // Only the two follow modes move the radial focal point; Fixed and an
        // unknown kwinrc value keep it centred (no off-centre radial).
        check("follows(Fixed)", Constants.gradientFollows(Constants.BackgroundGradientRotation.Fixed), false);
        check("follows(FollowCube)", Constants.gradientFollows(Constants.BackgroundGradientRotation.FollowCube), true);
        check("follows(Inverse)", Constants.gradientFollows(Constants.BackgroundGradientRotation.FollowCubeInverse), true);
        check("follows(unknown 7)", Constants.gradientFollows(7), false);
        check("follows(undefined)", Constants.gradientFollows(undefined), false);

        // Face opacity (ADR-021): rest vs rotation value, clamped to
        // [0.1, 1] (a fully invisible face cannot be picked), non-finite
        // falls back to the schema default of the active branch.
        check("face(rest 1, still)", Constants.faceOpacity(1, 0.7, false), 1);
        check("face(rot 0.7, rotating)", Constants.faceOpacity(1, 0.7, true), 0.7);
        check("face(rest 0.5, still)", Constants.faceOpacity(0.5, 0.7, false), 0.5);
        check("face(rot 1, rotating)", Constants.faceOpacity(0.5, 1, true), 1);
        check("face(rest 0, clamp)", Constants.faceOpacity(0, 0.7, false), 0.1);
        check("face(rot -1, clamp)", Constants.faceOpacity(1, -1, true), 0.1);
        check("face(rest 2, clamp)", Constants.faceOpacity(2, 0.7, false), 1);
        check("face(rest NaN -> 1)", Constants.faceOpacity(undefined, 0.7, false), 1);
        check("face(rot NaN -> 0.7)", Constants.faceOpacity(1, undefined, true), 0.7);
        // Number(null) is 0, not NaN: null/empty must read as "never
        // configured" and take the default of the active branch (ADR-022),
        // while a real 0 still clamps to the floor.
        check("face(rest null -> default)", Constants.faceOpacity(null, 0.7, false), 1);
        check("face(rot null -> default)", Constants.faceOpacity(1, null, true), 0.7);
        check("face(rest empty -> default)", Constants.faceOpacity("", 0.7, false), 1);
        check("face(rot 0 -> floor)", Constants.faceOpacity(1, 0, true), 0.1);
        check("face(rest numeric string)", Constants.faceOpacity("0.5", 0.7, false), 0.5);
        check("face(rest bad string -> 1)", Constants.faceOpacity("abc", 0.7, false), 1);
        check("face(rot undefined rotating)", Constants.faceOpacity(1, 0.7, undefined), 1);

        // Face fade duration: 0..1000 ms, 0 is a hard cut, non-finite -> 120.
        check("fade(120)", Constants.faceFadeDuration(120), 120);
        check("fade(0)", Constants.faceFadeDuration(0), 0);
        check("fade(1000)", Constants.faceFadeDuration(1000), 1000);
        check("fade(-5)", Constants.faceFadeDuration(-5), 0);
        check("fade(5000)", Constants.faceFadeDuration(5000), 1000);
        check("fade(undefined)", Constants.faceFadeDuration(undefined), 120);
        // null is "unset", not 0 ms: the default fade (ADR-022).
        check("fade(null)", Constants.faceFadeDuration(null), 120);
        check("fade(empty)", Constants.faceFadeDuration(""), 120);
        // Number(" ") is 0: a whitespace-only value is unset, not the floor.
        check("fade(whitespace)", Constants.faceFadeDuration("  "), 120);
        check("fade(string)", Constants.faceFadeDuration("abc"), 120);

        // Shape (ADR-025): the resolver mirrors backgroundMode — Cylinder is
        // the only value that survives; anything else (unknown index, string,
        // undefined) is Polygon, the virgin look.
        check("shape(Polygon)", Constants.shape(Constants.Shape.Polygon), Constants.Shape.Polygon);
        check("shape(Cylinder)", Constants.shape(Constants.Shape.Cylinder), Constants.Shape.Cylinder);
        check("shape(unknown 2)", Constants.shape(2), Constants.Shape.Polygon);
        check("shape(-1)", Constants.shape(-1), Constants.Shape.Polygon);
        check("shape(undefined)", Constants.shape(undefined), Constants.Shape.Polygon);
        check("shape(null)", Constants.shape(null), Constants.Shape.Polygon);
        check("shape(string)", Constants.shape("1"), Constants.Shape.Polygon);
        // Overlay names (ADR-023 pattern): short poly|cyl, unknown is named.
        check("shapeName(poly)", Constants.shapeName(Constants.Shape.Polygon), "poly");
        check("shapeName(cyl)", Constants.shapeName(Constants.Shape.Cylinder), "cyl");
        check("shapeName(unknown)", Constants.shapeName(7), "Unknown");
        check("shapeName(undefined)", Constants.shapeName(undefined), "Unknown");

        // Cylinder radius R = N(W+g)/2pi (ADR-025): the displacement clamps
        // to >= 0 (isometry cannot overlap arcs), unset/garbage gap reads 0,
        // and meaningless count/width answer 0 (safeViewRadius pins the
        // camera above it, the mesh renders nothing until it is valid).
        checkClose("R(4,2560,0)", Constants.cylinderRadius(4, 2560, 0), 4 * 2560 / (2 * Math.PI));
        checkClose("R(4,2560,100)", Constants.cylinderRadius(4, 2560, 100), 4 * 2660 / (2 * Math.PI));
        checkClose("R(3,1920,100)", Constants.cylinderRadius(3, 1920, 100), 3 * 2020 / (2 * Math.PI));
        checkClose("R negative clamps", Constants.cylinderRadius(4, 2560, -500), Constants.cylinderRadius(4, 2560, 0));
        checkClose("R null gap", Constants.cylinderRadius(4, 2560, null), Constants.cylinderRadius(4, 2560, 0));
        checkClose("R empty gap", Constants.cylinderRadius(4, 2560, ""), Constants.cylinderRadius(4, 2560, 0));
        checkClose("R NaN gap", Constants.cylinderRadius(4, 2560, NaN), Constants.cylinderRadius(4, 2560, 0));
        checkClose("R string inputs", Constants.cylinderRadius("4", "2560", "100"), 4 * 2660 / (2 * Math.PI));
        check("R NaN count", Constants.cylinderRadius(NaN, 2560, 100), 0);
        check("R zero count", Constants.cylinderRadius(0, 2560, 100), 0);
        check("R negative count", Constants.cylinderRadius(-3, 2560, 100), 0);
        check("R zero width", Constants.cylinderRadius(4, 0, 100), 0);
        check("R NaN width", Constants.cylinderRadius(4, NaN, 100), 0);
        check("R undefined", Constants.cylinderRadius(undefined, undefined, undefined), 0);

        // Arc angle theta = W/R (radians). With g = 0 the arcs close the
        // circle: theta must equal the polygon tick 2pi/N exactly.
        checkClose("theta closes N=4", Constants.cylinderArcAngle(2560, Constants.cylinderRadius(4, 2560, 0)), Math.PI / 2);
        checkClose("theta closes N=3", Constants.cylinderArcAngle(1920, Constants.cylinderRadius(3, 1920, 0)), 2 * Math.PI / 3);
        checkClose("theta with gap", Constants.cylinderArcAngle(2560, Constants.cylinderRadius(4, 2560, 100)), 2560 / Constants.cylinderRadius(4, 2560, 100));
        check("theta zero radius", Constants.cylinderArcAngle(2560, 0), 0);
        check("theta negative radius", Constants.cylinderArcAngle(2560, -5), 0);
        check("theta NaN width", Constants.cylinderArcAngle(NaN, 100), 0);
        check("theta undefined", Constants.cylinderArcAngle(undefined, undefined), 0);
        check("segments fixed", Constants.CYLINDER_SEGMENTS, 64);

        // Arc geometry (ADR-025): structure only here — check-cylinder.py
        // validates the REAL ProceduralMesh (radius, isometry, winding, arc
        // length) offscreen. Degenerate input answers empty arrays.
        const arc = Constants.cylinderArcGeometry(2560, 1440, Constants.cylinderRadius(4, 2560, 100), Constants.CYLINDER_SEGMENTS);
        check("arc positions", arc.positions.length, 130);
        check("arc normals", arc.normals.length, 130);
        check("arc uvs", arc.uvs.length, 130);
        check("arc indexes", arc.indexes.length, 384);
        check("arc degenerate R", Constants.cylinderArcGeometry(2560, 1440, 0, 64).positions.length, 0);
        check("arc degenerate W", Constants.cylinderArcGeometry(0, 1440, 100, 64).indexes.length, 0);
        check("arc degenerate H", Constants.cylinderArcGeometry(2560, 0, 100, 64).normals.length, 0);

        // Curved segment (ADR-025, 1-2 desktops): fixed 120-degree arcs.
        // R = 3W/2pi (W only — the linear gap does NOT apply), azimuths
        // 0 / 120 (and the polygon tick above 3, so the helper covers the
        // whole shape), turn caps 80 / 120 / 360.
        check("segments deg", Constants.CYLINDER_SEGMENT_DEG, 120);
        checkClose("Rseg(2560)", Constants.cylinderArcRadius(2560), 3 * 2560 / (2 * Math.PI));
        checkClose("Rseg(1920)", Constants.cylinderArcRadius(1920), 3 * 1920 / (2 * Math.PI));
        check("Rseg zero", Constants.cylinderArcRadius(0), 0);
        check("Rseg negative", Constants.cylinderArcRadius(-100), 0);
        check("Rseg NaN", Constants.cylinderArcRadius(NaN), 0);
        check("Rseg undefined", Constants.cylinderArcRadius(undefined), 0);
        check("Rseg string", Constants.cylinderArcRadius("2560"), Constants.cylinderArcRadius(2560));
        // theta of the segment arc must be 2pi/3: the generator closes the
        // 120-degree arc from R = 3W/2pi by construction.
        checkClose("theta segment", Constants.cylinderArcAngle(2560, Constants.cylinderArcRadius(2560)), 2 * Math.PI / 3);
        check("azim(0,1)", Constants.cylinderSegmentAzimuth(0, 1), 0);
        check("azim(1,1) clamped to one face", Constants.cylinderSegmentAzimuth(1, 1), 0);
        check("azim(0,2)", Constants.cylinderSegmentAzimuth(0, 2), 0);
        check("azim(1,2)", Constants.cylinderSegmentAzimuth(1, 2), 120);
        check("azim(1,3)", Constants.cylinderSegmentAzimuth(1, 3), 120);
        check("azim(3,4)", Constants.cylinderSegmentAzimuth(3, 4), 270);
        check("azim(1,4)", Constants.cylinderSegmentAzimuth(1, 4), 90);
        check("azim(NaN index)", Constants.cylinderSegmentAzimuth(NaN, 2), 0);
        check("azim(NaN count)", Constants.cylinderSegmentAzimuth(1, NaN), 0);
        check("azim(count 0)", Constants.cylinderSegmentAzimuth(1, 0), 0);
        check("azim(count 1, high index)", Constants.cylinderSegmentAzimuth(5, 1), 0);
        check("azim(count string 4)", Constants.cylinderSegmentAzimuth(2, "4"), 180);
        // Turn RANGES (ADR-025 pt.11, rectified): the band edges are the
        // last front-facing degrees. The symmetric ±80/±120 first chosen
        // left 20 degrees of mirrored back with one arc and parked the
        // camera at -120 — the centre of the gap — with two. null bound =
        // no limit. Strict count: a string "2" is garbage.
        check("range(1)[0]", Constants.cylinderAzimuthRange(1)[0], -60);
        check("range(1)[1]", Constants.cylinderAzimuthRange(1)[1], 60);
        check("range(2)[0]", Constants.cylinderAzimuthRange(2)[0], -60);
        check("range(2)[1]", Constants.cylinderAzimuthRange(2)[1], 180);
        check("range(3)[0]", Constants.cylinderAzimuthRange(3)[0], null);
        check("range(3)[1]", Constants.cylinderAzimuthRange(3)[1], null);
        check("range(4)", Constants.cylinderAzimuthRange(4)[0], null);
        check("range(0)", Constants.cylinderAzimuthRange(0)[1], null);
        check("range(NaN)", Constants.cylinderAzimuthRange(NaN)[0], null);
        check("range(string)", Constants.cylinderAzimuthRange("2")[0], null);
        // The flat sheet's symmetric caps as the same [min,max] shape
        // (ADR-024 behaviour, one mechanism): [-80,80] with one desktop,
        // open with two/three or garbage.
        check("flat(1)[0]", Constants.flatAzimuthRange(1)[0], -80);
        check("flat(1)[1]", Constants.flatAzimuthRange(1)[1], 80);
        check("flat(2)", Constants.flatAzimuthRange(2)[0], null);
        check("flat(3)", Constants.flatAzimuthRange(3)[1], null);
        check("flat(0)", Constants.flatAzimuthRange(0)[0], null);
        check("flat(NaN)", Constants.flatAzimuthRange(NaN)[0], null);
        // Dynamic culling tokens (ADR-025 pt.12; Cube maps 1/0 to the
        // Material enums symbolically — Qt 6.12.1 ints are Back=1,
        // Front=2, None=3, so raw ints must never travel from here).
        check("cull outside", Constants.cylinderCullMode(3000, 1000), 1);
        check("cull just past margin", Constants.cylinderCullMode(1051, 1000), 1);
        check("cull exact 1.05 margin", Constants.cylinderCullMode(1050, 1000), 0);
        check("cull inside", Constants.cylinderCullMode(900, 1000), 0);
        check("cull deep inside (minRadius case)", Constants.cylinderCullMode(600, 1000), 0);
        check("cull NaN camera", Constants.cylinderCullMode(NaN, 1000), 0);
        check("cull NaN radius", Constants.cylinderCullMode(3000, NaN), 0);
        check("cull zero radius", Constants.cylinderCullMode(3000, 0), 0);
        check("cull zero camera (unbound)", Constants.cylinderCullMode(0, 1000), 0);
        check("cull undefined", Constants.cylinderCullMode(undefined, undefined), 0);

        // Arrows (ADR-025 pt.13): the trace the reviewer measured. Segment
        // band [-60,180], faces [0,120], tick 120: the arrow lands on the
        // NEXT FACE in the requested direction, wrapping inside the band —
        // never a raw tick multiple clamped to the edge.
        const band = [-60, 180];
        const segFaces = [0, 120];
        check("arrow RIGHT 0", Constants.arrowAzimuth(0, 1, 120, band[0], band[1], segFaces), 120);
        check("arrow LEFT 0 wraps", Constants.arrowAzimuth(0, -1, 120, band[0], band[1], segFaces), 120);
        check("arrow RIGHT 120", Constants.arrowAzimuth(120, 1, 120, band[0], band[1], segFaces), 0);
        check("arrow LEFT 120", Constants.arrowAzimuth(120, -1, 120, band[0], band[1], segFaces), 0);
        // Off-face starts pick the nearest face in the direction.
        check("arrow RIGHT 45", Constants.arrowAzimuth(45, 1, 120, band[0], band[1], segFaces), 120);
        check("arrow LEFT 45", Constants.arrowAzimuth(45, -1, 120, band[0], band[1], segFaces), 0);
        // Band edges: LEFT at the left edge wraps to the highest face; RIGHT
        // at the right edge wraps to the lowest. No clamped no-ops.
        check("arrow LEFT -60", Constants.arrowAzimuth(-60, -1, 120, band[0], band[1], segFaces), 120);
        check("arrow RIGHT 180", Constants.arrowAzimuth(180, 1, 120, band[0], band[1], segFaces), 0);
        // One-face bands (flat sheet-1 [-80,80] and segment-1 [-60,60], tick
        // 360): the only face wraps to itself — delta 0, the arrow holds.
        // Parity with the old clamp (360 -> normalized -> 0 -> clamped 0).
        check("sheet1 RIGHT 0", Constants.arrowAzimuth(0, 1, 360, -80, 80, [0]), 0);
        check("sheet1 LEFT 0", Constants.arrowAzimuth(0, -1, 360, -80, 80, [0]), 0);
        check("sheet1 RIGHT 40", Constants.arrowAzimuth(40, 1, 360, -80, 80, [0]), 0);
        check("sheet1 LEFT -50", Constants.arrowAzimuth(-50, -1, 360, -80, 80, [0]), 0);
        check("seg1 LEFT -30", Constants.arrowAzimuth(-30, -1, 360, -60, 60, [0]), 0);
        // Open range: the pre-cylinder arithmetic VERBATIM (no normalize —
        // 450 stays 450; quaternion signs and slerp paths unchanged).
        check("open RIGHT 0", Constants.arrowAzimuth(0, 1, 90, null, null, [0, 90, 180, 270]), 90);
        check("open LEFT 0", Constants.arrowAzimuth(0, -1, 90, null, null, [0, 90, 180, 270]), -90);
        check("open RIGHT 240", Constants.arrowAzimuth(240, 1, 90, null, null, [0, 90, 180, 270]), 270);
        check("open RIGHT 270", Constants.arrowAzimuth(270, 1, 90, null, null, [0, 90, 180, 270]), 360);
        check("open RIGHT 359 verbatim", Constants.arrowAzimuth(359, 1, 90, null, null, [0, 90, 180, 270]), 450);
        check("open LEFT -1", Constants.arrowAzimuth(-1, -1, 90, null, null, [0, 90, 180, 270]), -90);
        check("open sheet2 RIGHT 180", Constants.arrowAzimuth(180, 1, 180, null, null, [0, 180]), 360);
        // Garbage.
        check("arrow NaN current", Constants.arrowAzimuth(NaN, 1, 120, band[0], band[1], segFaces), 0);
        check("arrow limited empty faces", Constants.arrowAzimuth(60, 1, 120, band[0], band[1], []), 60);
        check("arrow non-array faces", Constants.arrowAzimuth(60, 1, 120, band[0], band[1], undefined), 60);
        check("arrow open NaN tick", Constants.arrowAzimuth(70, 1, NaN, null, null, []), 70);
        // Selection, normalized with mirror: |a| <= 60 -> face 0, wider ->
        // face 1 (the band is 0..120 forward with the 120 gap behind); -1
        // when this is not a segment (drum counts, mid-sync 0) or garbage.
        check("segAt(0,1)", Constants.cylinderSegmentDesktopAt(0, 1), 0);
        check("segAt(80,1)", Constants.cylinderSegmentDesktopAt(80, 1), 0);
        check("segAt(0,2)", Constants.cylinderSegmentDesktopAt(0, 2), 0);
        check("segAt(59,2)", Constants.cylinderSegmentDesktopAt(59, 2), 0);
        check("segAt(60,2)", Constants.cylinderSegmentDesktopAt(60, 2), 0);
        check("segAt(61,2)", Constants.cylinderSegmentDesktopAt(61, 2), 1);
        check("segAt(120,2)", Constants.cylinderSegmentDesktopAt(120, 2), 1);
        check("segAt(180,2)", Constants.cylinderSegmentDesktopAt(180, 2), 1);
        check("segAt(-60,2)", Constants.cylinderSegmentDesktopAt(-60, 2), 0);
        check("segAt(-61,2) mirror", Constants.cylinderSegmentDesktopAt(-61, 2), 1);
        check("segAt(-120,2) mirror", Constants.cylinderSegmentDesktopAt(-120, 2), 1);
        check("segAt(181,2) wraps to -179", Constants.cylinderSegmentDesktopAt(181, 2), 1);
        check("segAt(300,2) wraps to -60", Constants.cylinderSegmentDesktopAt(300, 2), 0);
        check("segAt(480,2) wraps to 120", Constants.cylinderSegmentDesktopAt(480, 2), 1);
        check("segAt(NaN,2)", Constants.cylinderSegmentDesktopAt(NaN, 2), -1);
        check("segAt(undefined,1)", Constants.cylinderSegmentDesktopAt(undefined, 1), -1);
        check("segAt(null,1) reads 0", Constants.cylinderSegmentDesktopAt(null, 1), 0);
        check("segAt('abc',2)", Constants.cylinderSegmentDesktopAt("abc", 2), -1);
        check("segAt(0,0) mid-sync", Constants.cylinderSegmentDesktopAt(0, 0), -1);
        check("segAt(0,3) drum", Constants.cylinderSegmentDesktopAt(0, 3), -1);
        check("segAt(0,undefined)", Constants.cylinderSegmentDesktopAt(0, undefined), -1);

        // Sheet azimuth limit (ADR-024): 1 desktop caps at ±80, everything
        // else answers 360 ("no limit": 2 faces both real, >=3 is the polygon).
        check("limit(0)", Constants.sheetAzimuthLimit(0), 360);
        check("limit(1)", Constants.sheetAzimuthLimit(1), 80);
        check("limit(2)", Constants.sheetAzimuthLimit(2), 360);
        check("limit(3)", Constants.sheetAzimuthLimit(3), 360);
        check("limit(4)", Constants.sheetAzimuthLimit(4), 360);
        check("limit(-2)", Constants.sheetAzimuthLimit(-2), 360);
        check("limit(undefined)", Constants.sheetAzimuthLimit(undefined), 360);
        check("limit(null)", Constants.sheetAzimuthLimit(null), 360);
        check("limit(string)", Constants.sheetAzimuthLimit("1"), 360);
        check("limit(1.0 number)", Constants.sheetAzimuthLimit(1.0), 80);

        // Normalization to (-180, 180]: wrap point lands on +180, non-finite
        // reads as the front view (0).
        checkClose("norm(0)", Constants.normalizeSheetAzimuth(0), 0);
        checkClose("norm(90)", Constants.normalizeSheetAzimuth(90), 90);
        checkClose("norm(180)", Constants.normalizeSheetAzimuth(180), 180);
        checkClose("norm(-180)", Constants.normalizeSheetAzimuth(-180), 180);
        checkClose("norm(181)", Constants.normalizeSheetAzimuth(181), -179);
        checkClose("norm(360)", Constants.normalizeSheetAzimuth(360), 0);
        checkClose("norm(-360)", Constants.normalizeSheetAzimuth(-360), 0);
        checkClose("norm(540)", Constants.normalizeSheetAzimuth(540), 180);
        checkClose("norm(-190)", Constants.normalizeSheetAzimuth(-190), 170);
        checkClose("norm(NaN)", Constants.normalizeSheetAzimuth(NaN), 0);
        check("norm(undefined)", Constants.normalizeSheetAzimuth(undefined), 0);
        check("norm(string 45)", Constants.normalizeSheetAzimuth("45"), 45);

        // Target clamp (arrows, states) with an explicit [min,max] range:
        // open range returns the angle VERBATIM (pre-sheet parity: no
        // normalization, so the Behavior never slerps the opposite-sign
        // equivalent quaternion); a real range normalizes to (-180,180] and
        // then clamps — symmetric ranges behave EXACTLY like the retired
        // clampSheetAzimuth. The drag path does not use this helper:
        // CubeCameraController clamps the RAW sum between the bounds (190
        // degrees of drag sit at 180, the band edge — no wrap, no jump).
        checkClose("clamp(40, -80, 80)", Constants.clampAzimuthRange(40, -80, 80), 40);
        checkClose("clamp(90, -80, 80)", Constants.clampAzimuthRange(90, -80, 80), 80);
        checkClose("clamp(-95, -80, 80)", Constants.clampAzimuthRange(-95, -80, 80), -80);
        checkClose("clamp(200, -80, 80)", Constants.clampAzimuthRange(200, -80, 80), -80);
        checkClose("clamp(-200, -80, 80)", Constants.clampAzimuthRange(-200, -80, 80), 80);
        checkClose("clamp(1000, -80, 80)", Constants.clampAzimuthRange(1000, -80, 80), -80); // 1000 -> 280 -> -80
        checkClose("clamp(90, 0, 0)", Constants.clampAzimuthRange(90, 0, 0), 0);
        checkClose("clamp(90, -30, -30)", Constants.clampAzimuthRange(90, -30, -30), -30); // lo<=hi guardless: min(−30,max(−30,90))
        checkClose("clamp(NaN, -80, 80)", Constants.clampAzimuthRange(NaN, -80, 80), 0);
        checkClose("clamp(Infinity, -80, 80)", Constants.clampAzimuthRange(Infinity, -80, 80), 0);
        // Open range (null/null) = verbatim, exactly the old limit-360 path.
        checkClose("clamp(360, null, null) verbatim", Constants.clampAzimuthRange(360, null, null), 360);
        checkClose("clamp(180, null, null) verbatim", Constants.clampAzimuthRange(180, null, null), 180);
        checkClose("clamp(-180, null, null) verbatim", Constants.clampAzimuthRange(-180, null, null), -180);
        checkClose("clamp(270, null, null) verbatim", Constants.clampAzimuthRange(270, null, null), 270);
        checkClose("clamp(270, null, 361) verbatim", Constants.clampAzimuthRange(270, null, 361), 270);
        checkClose("clamp(90, NaN, NaN) verbatim", Constants.clampAzimuthRange(90, NaN, NaN), 90);
        checkClose("clamp(90, undefined, undefined) verbatim", Constants.clampAzimuthRange(90, undefined, undefined), 90);
        // The asymmetric segment band [-60, 180]: the arc centres 0 and 120
        // pass through; anything past an edge clamps to that EDGE in
        // normalized space (200 -> -160 -> -60, the left edge — no teleport
        // across the gap; the drag path clamps raw and sits at 180 instead,
        // which is CubeCameraController's own business, not this helper's).
        checkClose("clamp(0, -60, 180)", Constants.clampAzimuthRange(0, -60, 180), 0);
        checkClose("clamp(120, -60, 180)", Constants.clampAzimuthRange(120, -60, 180), 120);
        checkClose("clamp(179, -60, 180)", Constants.clampAzimuthRange(179, -60, 180), 179);
        checkClose("clamp(-61, -60, 180)", Constants.clampAzimuthRange(-61, -60, 180), -60);
        checkClose("clamp(181, -60, 180)", Constants.clampAzimuthRange(181, -60, 180), -60); // 181 -> -179 -> -60
        checkClose("clamp(190, -60, 180)", Constants.clampAzimuthRange(190, -60, 180), -60); // 190 -> -170 -> -60
        checkClose("clamp(200, -60, 180)", Constants.clampAzimuthRange(200, -60, 180), -60); // 200 -> -160 -> -60
        checkClose("clamp(240, -60, 180)", Constants.clampAzimuthRange(240, -60, 180), -60); // arrow tick 240 -> -120 -> -60

        // Which face looks at the camera: front within ±90, back beyond it
        // (2 desktops); -1 = not a sheet (0 mid-sync, >=3) or garbage azimuth.
        check("face(0, 2)", Constants.sheetDesktopAt(0, 2), 0);
        check("face(89, 2)", Constants.sheetDesktopAt(89, 2), 0);
        check("face(90, 2)", Constants.sheetDesktopAt(90, 2), 0);
        check("face(91, 2)", Constants.sheetDesktopAt(91, 2), 1);
        check("face(180, 2)", Constants.sheetDesktopAt(180, 2), 1);
        check("face(-180, 2)", Constants.sheetDesktopAt(-180, 2), 1);
        check("face(-91, 2)", Constants.sheetDesktopAt(-91, 2), 1);
        // Boundary: -90 is exactly the front/back border (inclusive front), and
        // 270 normalizes to -90 -> also the front face.
        check("face(-90, 2)", Constants.sheetDesktopAt(-90, 2), 0);
        check("face(270, 2)", Constants.sheetDesktopAt(270, 2), 0);
        check("face(200, 2)", Constants.sheetDesktopAt(200, 2), 1);
        check("face(-200, 2)", Constants.sheetDesktopAt(-200, 2), 1);
        check("face(0, 1)", Constants.sheetDesktopAt(0, 1), 0);
        check("face(80, 1)", Constants.sheetDesktopAt(80, 1), 0);
        check("face(-80, 1)", Constants.sheetDesktopAt(-80, 1), 0);
        check("face(300, 1)", Constants.sheetDesktopAt(300, 1), 0);
        check("face(0, 0)", Constants.sheetDesktopAt(0, 0), -1);
        check("face(0, 3)", Constants.sheetDesktopAt(0, 3), -1);
        check("face(0, 4)", Constants.sheetDesktopAt(0, 4), -1);
        check("face(NaN, 2)", Constants.sheetDesktopAt(NaN, 2), -1);
        check("face(undefined, 2)", Constants.sheetDesktopAt(undefined, 2), -1);
        check("face(null, 1)", Constants.sheetDesktopAt(null, 1), 0);
        check("face('abc', 2)", Constants.sheetDesktopAt("abc", 2), -1);
        check("face(45, undefined)", Constants.sheetDesktopAt(45, undefined), -1);

        // Url entry: url value or string, empty/undefined/null -> no image,
        // remote schemes rejected (the compositor must not fetch the network).
        check("source(file url)", Constants.backgroundImageSource(h.fileUrl), "file:///home/user/My Wall.jpg");
        check("source(empty url)", Constants.backgroundImageSource(h.emptyUrl), "");
        check("source(bare url value)", Constants.backgroundImageSource(h.bareUrl), "/home/user/wall.jpg");
        check("source(absolute path)", Constants.backgroundImageSource("/home/user/My Wall.jpg"), "/home/user/My Wall.jpg");
        check("source(file url string)", Constants.backgroundImageSource("file:///home/user/w.jpg"), "file:///home/user/w.jpg");
        check("source(image provider)", Constants.backgroundImageSource("image://wallpaper/0"), "image://wallpaper/0");
        check("source(empty string)", Constants.backgroundImageSource(""), "");
        check("source(undefined)", Constants.backgroundImageSource(undefined), "");
        check("source(null)", Constants.backgroundImageSource(null), "");
        check("source(http)", Constants.backgroundImageSource("http://example.com/sky.jpg"), "");
        check("source(smb)", Constants.backgroundImageSource("smb://host/sky.jpg"), "");

        // Video source: same local-only rule as the image, but a clip must be a
        // real file. image: is rejected (there is no video provider behind it)
        // and so is every remote scheme.
        check("video(file url)", Constants.videoSource(h.fileUrl), "file:///home/user/My Wall.jpg");
        check("video(bare url value)", Constants.videoSource(h.bareUrl), "/home/user/wall.jpg");
        check("video(file url string)", Constants.videoSource("file:///home/user/clip.mp4"), "file:///home/user/clip.mp4");
        check("video(absolute path)", Constants.videoSource("/home/user/clip.mp4"), "/home/user/clip.mp4");
        check("video(empty url)", Constants.videoSource(h.emptyUrl), "");
        check("video(empty string)", Constants.videoSource(""), "");
        check("video(undefined)", Constants.videoSource(undefined), "");
        check("video(null)", Constants.videoSource(null), "");
        check("video(image provider)", Constants.videoSource("image://wallpaper/0"), "");
        check("video(http)", Constants.videoSource("http://example.com/clip.mp4"), "");
        check("video(smb)", Constants.videoSource("smb://host/clip.mp4"), "");
    }
}
