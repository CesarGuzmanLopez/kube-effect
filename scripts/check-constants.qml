import QtQuick
import "../package/contents/ui/constants.js" as Constants
import "../package/contents/ui/capGeometry.js" as CapGeo

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

        // isFiniteNumber keeps the coercion of the historical global isFinite().
        // KConfig can hand a numeric string; Number.isFinite() alone would reject
        // it and silently fall back to the schema default. The mechanical S7773
        // fix (isFinite -> Number.isFinite wrapped in a Number()) is proven to be
        // a drop-in for every input the helpers actually see.
        check("isFiniteNumber(50)", Constants.isFiniteNumber(50), true);
        check("isFiniteNumber(numeric string)", Constants.isFiniteNumber("50"), true);
        check("isFiniteNumber(0 string)", Constants.isFiniteNumber("0"), true);
        check("isFiniteNumber(empty string)", Constants.isFiniteNumber(""), true);
        check("isFiniteNumber(whitespace)", Constants.isFiniteNumber("  "), true);
        check("isFiniteNumber(NaN)", Constants.isFiniteNumber(NaN), false);
        check("isFiniteNumber(Infinity)", Constants.isFiniteNumber(Infinity), false);
        check("isFiniteNumber(-Infinity)", Constants.isFiniteNumber(-Infinity), false);
        check("isFiniteNumber(non-numeric string)", Constants.isFiniteNumber("abc"), false);
        check("isFiniteNumber(null)", Constants.isFiniteNumber(null), true);
        check("isFiniteNumber(undefined)", Constants.isFiniteNumber(undefined), false);
        // Identical verdict to the old global on the tricky input: the helper is
        // a faithful clone, not a stricter filter (empty/whitespace stay finite
        // here; turning them into "unset" is finiteOr's separate job, tested at
        // the dim(on, empty) case above, which lands on the default).
        check("isFiniteNumber matches isFinite('50')", Constants.isFiniteNumber("50"), isFinite("50"));
        check("isFiniteNumber matches isFinite('')", Constants.isFiniteNumber(""), isFinite(""));
        // End-to-end: a numeric string is COERCED, not dropped to the default.
        // The expected value differs from the schema default, so a regression to
        // bare Number.isFinite() (which would return 0.4 / 0.5 / 0.8 / 1 here)
        // cannot pass these.
        check("dim(on, numeric string 100)", Constants.dimOpacity(true, "100"), 1);
        check("dim(on, numeric string 60)", Constants.dimOpacity(true, "60"), 0.6);
        check("stop(numeric string 100)", Constants.gradientStopPosition("100"), 1);
        check("capOpacity(numeric string 100)", Constants.capOpacity("100"), 1);
        check("faceOpacity(numeric string rest)", Constants.faceOpacity("0.5", 0.7, false), 0.5);
        check("fade(numeric string 300)", Constants.faceFadeDuration("300"), 300);

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

        // Three-slot drum (ADR-025 pt.11 re-rectified, ADR-026): with 1-2
        // desktops and Shape = Cylinder the drum formula runs with N = 3 —
        // R = 3(W + g)/2pi WITH the user's linear gap (the fixed 3W/2pi is
        // gone), the azimuths are the bare tick grid (slot i at 120·i), the
        // empty slots have no delegate (hull shows through) and the turn
        // range stays OPEN. cylinderArcRadius / cylinderSegmentAzimuth /
        // cylinderAzimuthRange / cylinderSegmentDesktopAt (the capped band
        // design) are retired helpers; the wiring check exercises the grid
        // through the real Cube instead.
        checkClose("R slots(2560,0)", Constants.cylinderRadius(3, 2560, 0), 3 * 2560 / (2 * Math.PI));
        checkClose("R slots(2560,100)", Constants.cylinderRadius(3, 2560, 100), 3 * 2660 / (2 * Math.PI));
        checkClose("R slots neg g clamps", Constants.cylinderRadius(3, 2560, -500), Constants.cylinderRadius(3, 2560, 0));
        // theta of the 3-slot arc with g = 0 is exactly 120 degrees: the
        // generator closes the circle from R = 3W/2pi by construction.
        checkClose("theta slots closes N=3", Constants.cylinderArcAngle(2560, Constants.cylinderRadius(3, 2560, 0)), 2 * Math.PI / 3);
        // (The band-era azim()/range() checks died with
        // cylinderSegmentAzimuth/cylinderAzimuthRange — see the routing
        // checks below, which are what the camera actually consults.)
        // The flat sheet's symmetric caps as the same [min,max] shape
        // (ADR-024 behaviour, one mechanism): [-80,80] with one desktop,
        // open with two/three or garbage.
        check("flat(1)[0]", Constants.flatAzimuthRange(1)[0], -80);
        check("flat(1)[1]", Constants.flatAzimuthRange(1)[1], 80);
        check("flat(2)", Constants.flatAzimuthRange(2)[0], null);
        check("flat(3)", Constants.flatAzimuthRange(3)[1], null);
        check("flat(0)", Constants.flatAzimuthRange(0)[0], null);
        check("flat(NaN)", Constants.flatAzimuthRange(NaN)[0], null);
        // Routing (ADR-026, three-slot recast): which range ScreenView
        // actually gets, by shape + mesh. The inline ternary it replaced
        // was untested and swapping the branches kept the gate green.
        // Polygon keeps the flat sheet caps ([-80,80] with one desktop,
        // open otherwise); EVERY Cylinder with the arc mesh — drum at 3+
        // and the three-slot drum at 1-2 — turns OPEN (the capped segment
        // band was retired by the user: jumps, choppy feel); a Cylinder
        // WITHOUT the mesh (QtQuick3D.Helpers missing) behaves exactly
        // like the polygon, sheet included.
        check("route(poly,1)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Polygon, 1, false)), "[-80,80]");
        check("route(poly,1,mesh-ignored)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Polygon, 1, true)), "[-80,80]");
        check("route(poly,2)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Polygon, 2, false)), "[null,null]");
        check("route(poly,3)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Polygon, 3, false)), "[null,null]");
        check("route(cyl,1,mesh) open", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Cylinder, 1, true)), "[null,null]");
        check("route(cyl,2,mesh) open", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Cylinder, 2, true)), "[null,null]");
        check("route(cyl,3,mesh)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Cylinder, 3, true)), "[null,null]");
        check("route(cyl,1,no mesh)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Cylinder, 1, false)), "[-80,80]");
        check("route(cyl,2,no mesh)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Cylinder, 2, false)), "[null,null]");
        check("route(cyl,0,mesh) mid-sync", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Cylinder, 0, true)), "[null,null]");
        check("route(unknown shape)", JSON.stringify(Constants.azimuthRangeFor(7, 1, true)), "[-80,80]");
        check("route(undefined mesh)", JSON.stringify(Constants.azimuthRangeFor(Constants.Shape.Cylinder, 2, undefined)), "[null,null]");
        check("route(cyl,2,open feeds clamp verbatim)", Constants.clampAzimuthRange(200, ...Constants.azimuthRangeFor(Constants.Shape.Cylinder, 2, true)), 200);
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

        // Arrows (ADR-025 pt.13) on a LIMITED asymmetric range — the
        // generic math the helper still guarantees even though no shape
        // asks for an asymmetric band today (the segment band was retired
        // with the three-slot drum; sheet-1's range is symmetric). The
        // arrow lands on the NEXT FACE in the requested direction,
        // wrapping inside the range — never a raw tick clamped to an edge.
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
        // One-face band (flat sheet-1 [-80,80], tick 360): the only face
        // wraps to itself — delta 0, the arrow holds. Parity with the old
        // clamp (360 -> normalized -> 0 -> clamped 0). (segment-1's
        // [-60,60] band is retired; the three-slot drum takes the open
        // grid checks above.)
        check("sheet1 RIGHT 0", Constants.arrowAzimuth(0, 1, 360, -80, 80, [0]), 0);
        check("sheet1 LEFT 0", Constants.arrowAzimuth(0, -1, 360, -80, 80, [0]), 0);
        check("sheet1 RIGHT 40", Constants.arrowAzimuth(40, 1, 360, -80, 80, [0]), 0);
        check("sheet1 LEFT -50", Constants.arrowAzimuth(-50, -1, 360, -80, 80, [0]), 0);
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
        // Cylinder arrows with 1-2 desktops (three-slot drum, OPEN range):
        // the tick grid has HOLES (slot 2 at 240 with two faces), so the
        // arrows walk the REAL faces with a full wrap (ADR-026b) — the
        // regression the user measured was parking on the empty slot where
        // Enter is the guarded no-op: «no se puede pasar». n=1: the only
        // real face is the standing one — no-op both directions. n=2: 0 <->
        // 120 from BOTH sides, 240 never a stop. The returned representative
        // keeps the rotation the short way (the slerp rule); modulo 360 it is
        // congruent with a real face azimuth.
        check("cyl1 RIGHT 0 no-op", Constants.arrowAzimuth(0, 1, 120, null, null, [0]), 0);
        check("cyl1 LEFT 0 no-op", Constants.arrowAzimuth(0, -1, 120, null, null, [0]), 0);
        // Threshold convention pinned (same strict < as the limited branch
        // and the verbatim grid path): EXACTLY 0.05*tick away (6.0 deg at
        // tick 120) counts as NOT standing -> the arrow snaps to the face;
        // one hair inside, the n=1 drum holds (no other stop exists).
        checkClose("cyl1 RIGHT 6 snaps (strict <)", Constants.arrowAzimuth(6, 1, 120, null, null, [0]), 0, 1e-6);
        checkClose("cyl1 LEFT 6 snaps (strict <)", Constants.arrowAzimuth(6, -1, 120, null, null, [0]), 0, 1e-6);
        checkClose("cyl1 RIGHT -6 snaps (strict <)", Constants.arrowAzimuth(-6, 1, 120, null, null, [0]), 0, 1e-6);
        check("cyl1 RIGHT 5.9 holds", Constants.arrowAzimuth(5.9, 1, 120, null, null, [0]), 5.9);
        check("cyl1 LEFT 5.9 holds", Constants.arrowAzimuth(5.9, -1, 120, null, null, [0]), 5.9);
        checkClose("cyl1 RIGHT 45 lands on face 0", Constants.arrowAzimuth(45, 1, 120, null, null, [0]), 0, 1e-6);
        checkClose("cyl1 LEFT -45 lands on face 0", Constants.arrowAzimuth(-45, -1, 120, null, null, [0]), 0, 1e-6);
        check("cyl arrow RIGHT 240 (n=1, short way to 0)", Constants.arrowAzimuth(240, 1, 120, null, null, [0]), 360);
        checkClose("cyl2 RIGHT 0", Constants.arrowAzimuth(0, 1, 120, null, null, [0, 120]), 120, 1e-6);
        checkClose("cyl2 LEFT 0", Constants.arrowAzimuth(0, -1, 120, null, null, [0, 120]), 120, 1e-6);
        checkClose("cyl2 RIGHT 120", Constants.arrowAzimuth(120, 1, 120, null, null, [0, 120]), 0, 1e-6);
        checkClose("cyl2 LEFT 120", Constants.arrowAzimuth(120, -1, 120, null, null, [0, 120]), 0, 1e-6);
        // From the empty slot itself and from the off-grid stuck point the
        // user measured (yaw=-103.9, parked by a drag): the arrows escape to
        // a real face in the requested direction.
        checkClose("cyl2 RIGHT from hole 240", Constants.arrowAzimuth(-120, 1, 120, null, null, [0, 120]), 0, 1e-6);
        checkClose("cyl2 LEFT from hole 240", Constants.arrowAzimuth(-120, -1, 120, null, null, [0, 120]), -240, 1e-6);
        checkClose("cyl2 RIGHT off-grid", Constants.arrowAzimuth(-103.9, 1, 120, null, null, [0, 120]), 0, 1e-6);
        checkClose("cyl2 LEFT off-grid", Constants.arrowAzimuth(-103.9, -1, 120, null, null, [0, 120]), -240, 1e-6);
        // After a full spin the representative keeps the short path: 360 ->
        // 480 (not 120: a -240 turn backwards would make the Behavior slerp
        // the long way).
        checkClose("cyl2 RIGHT 360", Constants.arrowAzimuth(360, 1, 120, null, null, [0, 120]), 480, 1e-6);
        // n=3: the grid is FULL, so the old tick arithmetic runs VERBATIM
        // (ADR-022/024 parity, 0 -> 120 -> 240 -> 360, no normalization).
        check("cyl3 RIGHT 0", Constants.arrowAzimuth(0, 1, 120, null, null, [0, 120, 240]), 120);
        check("cyl3 LEFT 0", Constants.arrowAzimuth(0, -1, 120, null, null, [0, 120, 240]), -120);
        check("cyl3 RIGHT 240", Constants.arrowAzimuth(240, 1, 120, null, null, [0, 120, 240]), 360);
        check("cyl3 RIGHT 359 verbatim", Constants.arrowAzimuth(359, 1, 120, null, null, [0, 120, 240]), 480);
        // desktopAzimuth for the states: slot number * tick (slot 0 with one
        // desktop -> the face is ALWAYS front-facing when the effect opens).
        checkClose("slot0 target verbatim", Constants.clampAzimuthRange(120 * 0, null, null), 0);
        checkClose("slot1 target verbatim", Constants.clampAzimuthRange(120 * 1, null, null), 120);

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
        // Generic ASYMMETRIC bounds (math kept for the helper contract;
        // the segment band [-60, 180] these were written for is retired —
        // every shape-with-mesh cylinder turns open now): centres pass
        // through, anything past an edge clamps to that EDGE in normalized
        // space (200 -> -160 -> -60; the drag path clamps raw and sits at
        // 180 instead, CubeCameraController's own business, not this
        // helper's).
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
        // Defence in depth over kwinrc (NOT a sandbox): a bare path must be
        // absolute, and traversal segments are rejected wherever they appear,
        // while the documented image: provider keeps working.
        check("source(relative bare path)", Constants.backgroundImageSource("sky.jpg"), "");
        check("source(dot relative)", Constants.backgroundImageSource("./sky.jpg"), "");
        check("source(traversal bare)", Constants.backgroundImageSource("../secrets/sky.jpg"), "");
        check("source(traversal nested)", Constants.backgroundImageSource("/home/user/../../etc/passwd"), "");
        check("source(traversal in file url)", Constants.backgroundImageSource("file:///home/user/../x.jpg"), "");
        // A single "." segment is not traversal, and a backslash is a legal file
        // name on Linux: both must keep working.
        check("source(dot dot file)", Constants.backgroundImageSource("/home/user/..jpg"), "/home/user/..jpg");
        check("source(backslash name)", Constants.backgroundImageSource("/home/user/a\\b.jpg"), "/home/user/a\\b.jpg");
        check("source(image provider with dots)", Constants.backgroundImageSource("image://wallpaper/a/../b"), "");

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
        // Same traversal/absolute rule as the image (a clip is file: only).
        check("video(relative bare path)", Constants.videoSource("clip.mp4"), "");
        check("video(traversal)", Constants.videoSource("/home/user/../../mnt/usb/clip.mp4"), "");
        check("video(absolute bare)", Constants.videoSource("/home/user/clip.mp4"), "/home/user/clip.mp4");
        check("video(smb)", Constants.videoSource("smb://host/clip.mp4"), "");

        // Caps (ADR-027): CapOpacity is an Int 0..100 converted to 0..1; 0 is
        // a real transparent cap (no enabled flag here), anything unusable
        // falls back to the schema default (80 %).
        check("capOpacity(0)", Constants.capOpacity(0), 0);
        check("capOpacity(50)", Constants.capOpacity(50), 0.5);
        check("capOpacity(80)", Constants.capOpacity(80), 0.8);
        check("capOpacity(100)", Constants.capOpacity(100), 1);
        check("capOpacity(150)", Constants.capOpacity(150), 1);
        check("capOpacity(-20)", Constants.capOpacity(-20), 0);
        check("capOpacity(null)", Constants.capOpacity(null), 0.8);
        check("capOpacity(empty)", Constants.capOpacity(""), 0.8);
        check("capOpacity(undefined)", Constants.capOpacity(undefined), 0.8);
        check("capOpacity(NaN)", Constants.capOpacity(NaN), 0.8);
        check("capOpacity(text)", Constants.capOpacity("eighty"), 0.8);

        // Enum resolvers: only the stored indexes pass; unknown values fall
        // back to the schema defaults (backgroundMode / imageFit pattern).
        check("capContent(Color)", Constants.capContent(Constants.CapContent.Color), Constants.CapContent.Color);
        check("capContent(Gradient)", Constants.capContent(Constants.CapContent.Gradient), Constants.CapContent.Gradient);
        check("capContent(Image)", Constants.capContent(Constants.CapContent.Image), Constants.CapContent.Image);
        // Arrow is a stored index 3 (ADR-027 amendment 2, appended last, the
        // schema DEFAULT: the marker is the only content that reads oriented).
        check("capContent(Arrow)", Constants.capContent(Constants.CapContent.Arrow), Constants.CapContent.Arrow);
        check("capContent(unknown 4)", Constants.capContent(4), Constants.CapContent.Color);
        check("capContent(texto basura)", Constants.capContent("basura"), Constants.CapContent.Color);
        check("capContent(-1)", Constants.capContent(-1), Constants.CapContent.Color);
        check("capContent(undefined)", Constants.capContent(undefined), Constants.CapContent.Color);
        check("capContent(string)", Constants.capContent("Gradient"), Constants.CapContent.Color);
        check("capGradientType(LinearVertical)", Constants.capGradientType(Constants.CapGradientType.LinearVertical), Constants.CapGradientType.LinearVertical);
        check("capGradientType(LinearHorizontal)", Constants.capGradientType(Constants.CapGradientType.LinearHorizontal), Constants.CapGradientType.LinearHorizontal);
        check("capGradientType(Radial)", Constants.capGradientType(Constants.CapGradientType.Radial), Constants.CapGradientType.Radial);
        check("capGradientType(unknown 5)", Constants.capGradientType(5), Constants.CapGradientType.LinearVertical);
        check("capGradientType(null)", Constants.capGradientType(null), Constants.CapGradientType.LinearVertical);
        check("capImageFit(Cover)", Constants.capImageFit(Constants.CapImageFit.Cover), Constants.CapImageFit.Cover);
        check("capImageFit(Contain)", Constants.capImageFit(Constants.CapImageFit.Contain), Constants.CapImageFit.Contain);
        check("capImageFit(Stretch)", Constants.capImageFit(Constants.CapImageFit.Stretch), Constants.CapImageFit.Stretch);
        check("capImageFit(unknown 9)", Constants.capImageFit(9), Constants.CapImageFit.Cover);
        check("capImageFit(undefined)", Constants.capImageFit(undefined), Constants.CapImageFit.Cover);

        // Cap image: same local-only filter as the background image (file: or
        // bare paths; image: allowed; remote schemes dropped).
        check("capSource(file url)", Constants.capImageSource(h.fileUrl), "file:///home/user/My Wall.jpg");
        check("capSource(bare url value)", Constants.capImageSource(h.bareUrl), "/home/user/wall.jpg");
        check("capSource(absolute path)", Constants.capImageSource("/home/user/cap.png"), "/home/user/cap.png");
        check("capSource(image provider)", Constants.capImageSource("image://wallpaper/0"), "image://wallpaper/0");
        check("capSource(empty url)", Constants.capImageSource(h.emptyUrl), "");
        check("capSource(undefined)", Constants.capImageSource(undefined), "");
        check("capSource(null)", Constants.capImageSource(null), "");
        check("capSource(http)", Constants.capImageSource("http://example.com/cap.png"), "");
        check("capSource(smb)", Constants.capImageSource("smb://host/cap.png"), "");

        // Cap generators (ADR-027 amendment): the polygon ring is stated in
        // each face's LOCAL frame. Regime d <= 0: the inscribed N-gon (its
        // edge midpoints on the apothem and on the face azimuth grid,
        // circumradius derived). Regime d > 0: 2N face-corner vertices at
        // hypot(apothem, faceWidth/2) — every face owns an exact -W/2/+W/2
        // side on its plane, closed by gap chords that stay INSIDE the
        // planes. Flat y = 0, +Y normals, centred UVs, CCW fan (cross along
        // +Y). Degenerate inputs (sides < 3, apothem or faceWidth or
        // halfHeight <= 0, non-finite) answer EMPTY arrays (mid-sync
        // contract, like the arc generator).
        const apothem = 1200;
        const capW = 2560;
        const sides = 5;
        const halfHeight = 720;
        const circum = apothem / Math.cos(Math.PI / sides);
        const capPoly = CapGeo.capPolygonGeometry(apothem, capW, sides, halfHeight);
        check("capPoly vertices (d<=0 branch)", capPoly.positions.length, sides + 1);
        check("capPoly triangles", capPoly.indexes.length, sides * 3);
        check("capPoly centre", capPoly.positions[0].x === 0 && capPoly.positions[0].y === 0 && capPoly.positions[0].z === 0, true);
        let capOnRing = true;
        let capFlat = true;
        let capUp = true;
        for (let i = 0; i <= sides; ++i) {
            const p = capPoly.positions[i];
            if (!isFinite(p.x) || !isFinite(p.y) || !isFinite(p.z) || Math.abs(p.y) > 1e-9) {
                capFlat = false;
            }
            // Qt.vector3d stores float32: compare with a radius-scaled
            // epsilon (the check-cap.py convention), never a 1e-9 double.
            if (i > 0 && Math.abs(Math.hypot(p.x, p.z) - circum) > 1e-6 * circum) {
                capOnRing = false;
            }
            const n = capPoly.normals[i];
            if (Math.abs(n.x) > 1e-9 || Math.abs(n.y - 1) > 1e-9 || Math.abs(n.z) > 1e-9) {
                capUp = false;
            }
        }
        check("capPoly flat ring at circumradius", capFlat && capOnRing, true);
        check("capPoly normals +Y", capUp, true);
        let capMidApothem = true;
        let capMidGrid = true;
        let capWinding = true;
        const step = 2 * Math.PI / sides;
        for (let k = 0; k < sides; ++k) {
            const a = capPoly.positions[1 + k];
            const b = capPoly.positions[1 + (k + 1) % sides];
            const mid = Math.hypot((a.x + b.x) / 2, (a.z + b.z) / 2);
            if (Math.abs(mid - apothem) > 1e-6 * apothem) {
                capMidApothem = false;
            }
            const angle = Math.atan2((a.x + b.x) / 2, (a.z + b.z) / 2);
            const rem = ((angle % step) + step) % step;
            // float32 coordinates carry ~1e-7 rad of angular noise here.
            if (Math.min(rem, step - rem) > 1e-5) {
                capMidGrid = false;
            }
            const i0 = capPoly.indexes[k * 3];
            const i1 = capPoly.indexes[k * 3 + 1];
            const i2 = capPoly.indexes[k * 3 + 2];
            if (i0 !== 0 || i1 < 1 || i1 > sides || i2 < 1 || i2 > sides) {
                capWinding = false;
                continue;
            }
            const p1 = capPoly.positions[i1];
            const p2 = capPoly.positions[i2];
            if (p1.z * p2.x - p1.x * p2.z <= 0) {
                capWinding = false;
            }
        }
        check("capPoly edge midpoints on the apothem", capMidApothem, true);
        check("capPoly edge midpoints on the face grid", capMidGrid, true);
        check("capPoly fan CCW seen from +Y", capWinding, true);
        let capUvOk = true;
        for (let i = 0; i <= sides; ++i) {
            const uv = capPoly.uvs[i];
            const p = capPoly.positions[i];
            if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 || Math.abs(uv.x - (0.5 + p.x / (2 * circum))) > 1e-6 || Math.abs(uv.y - (0.5 + p.z / (2 * circum))) > 1e-6) {
                capUvOk = false;
            }
        }
        check("capPoly centred UVs in [0,1]", capUvOk, true);

        // The corners regime: 5 sides with a face whose no-displacement
        // apothem (1280 / tan 36deg = 1761.8) sits ABOVE the live apothem
        // puts the faces apart (d > 0): the ring must present two corners
        // per face at hypot(apothem, faceWidth/2), each face owning a side
        // that lies ON its plane across exactly the face width, and no
        // vertex may stand outside a plane or past a corner (the local-frame
        // bound — the ring's max |x| legitimately exceeds faceWidth/2).
        const poke = CapGeo.capPolygonGeometry(1861.8, capW, 5, halfHeight);
        check("capPoly corners vertices (d>0 branch)", poke.positions.length, 11);
        check("capPoly corners triangles", poke.indexes.length, 30);
        const cornerRho = Math.hypot(1861.8, capW / 2);
        let cornersRing = true;
        let insidePlanes = true;
        let insideCorners = true;
        let onAnyPlane = true;
        for (let i = 1; i < poke.positions.length; ++i) {
            const p = poke.positions[i];
            if (Math.abs(p.y) > 1e-9 || Math.abs(Math.hypot(p.x, p.z) - cornerRho) > 1e-6 * cornerRho) {
                cornersRing = false;
            }
            let onPlane = false;
            for (let k = 0; k < 5; ++k) {
                const theta = (2 * Math.PI / 5) * k;
                const dotN = p.x * Math.sin(theta) + p.z * Math.cos(theta);
                if (dotN > 1861.8 + 1e-6 * cornerRho) {
                    insidePlanes = false;
                }
                if (Math.abs(dotN - 1861.8) <= 1e-6 * cornerRho) {
                    onPlane = true;
                    const dotT = p.x * Math.cos(theta) - p.z * Math.sin(theta);
                    if (Math.abs(dotT) > capW / 2 + 1e-6 * cornerRho) {
                        insideCorners = false;
                    }
                }
            }
            if (!onPlane) {
                onAnyPlane = false;
            }
        }
        check("capPoly corners ring at hypot(a, W/2), flat", cornersRing, true);
        check("capPoly corners inside every face plane", insidePlanes, true);
        check("capPoly corners within their face widths", insideCorners, true);
        check("capPoly corners every vertex on its plane", onAnyPlane, true);
        const capDisc = CapGeo.capDiscGeometry(800, 64, halfHeight);
        check("capDisc vertices", capDisc.positions.length, 65);
        check("capDisc triangles", capDisc.indexes.length, 64 * 3);
        let capDiscRing = true;
        for (let k = 1; k <= 64; ++k) {
            const p = capDisc.positions[k];
            if (Math.abs(Math.hypot(p.x, p.z) - 800) > 1e-6 * 800 || Math.abs(p.y) > 1e-9) {
                capDiscRing = false;
            }
        }
        check("capDisc ring at R, flat", capDiscRing, true);
        check("capDisc degenerate radius", CapGeo.capDiscGeometry(0, 64, halfHeight).positions.length, 0);
        check("capDisc few segments", CapGeo.capDiscGeometry(800, 2, halfHeight).positions.length, 0);
        check("capPoly sides below 3", CapGeo.capPolygonGeometry(1200, capW, 2, halfHeight).positions.length, 0);
        check("capPoly negative apothem", CapGeo.capPolygonGeometry(-5, capW, 5, halfHeight).positions.length, 0);
        check("capPoly zero faceWidth", CapGeo.capPolygonGeometry(1200, 0, 5, halfHeight).positions.length, 0);
        check("capPoly negative faceWidth", CapGeo.capPolygonGeometry(1200, -10, 5, halfHeight).positions.length, 0);
        check("capPoly zero halfHeight", CapGeo.capPolygonGeometry(1200, capW, 5, 0).positions.length, 0);
        check("capPoly garbage input", CapGeo.capPolygonGeometry("x", "y", "z", "w").positions.length, 0);
    }
}
